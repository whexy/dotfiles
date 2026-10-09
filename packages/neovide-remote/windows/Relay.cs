using System;
using System.Diagnostics;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Threading.Tasks;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using System.Xml;
using System.Reflection;

[assembly: AssemblyTitle("Neovide Remote")]
[assembly: AssemblyProduct("Neovide Remote")]

public static class NeovideRemoteRelay
{
    [STAThread]
    public static void Main(string[] args)
    {
        try
        {
            if (args.Length != 1 || !Regex.IsMatch(args[0],
                @"^vscode://(vscode-remote/ssh-remote\+[^/]+/|file/)"))
                throw new Exception("Expected a vscode:// SSH remote or file URL.");
            var config = new XmlDocument();
            config.Load(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "config.xml"));
            string helper = config.DocumentElement["Helper"].InnerText;
            if (!Regex.IsMatch(helper, @"^[A-Za-z0-9/._+-]+$"))
                throw new Exception("Invalid WSL helper path.");
            // Encoding keeps URL text out of Windows command-line and WSL shell syntax.
            string encoded = Convert.ToBase64String(Encoding.UTF8.GetBytes(args[0]));
            Run(config.DocumentElement["Neovide"].InnerText, helper,
                config.DocumentElement["Distribution"].InnerText, encoded);
        }
        catch (Exception error)
        {
            File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "relay.log"),
                DateTime.Now.ToString("o") + " " + error.ToString() + Environment.NewLine);
            MessageBox.Show(error.Message, "Neovide Remote", MessageBoxButtons.OK, MessageBoxIcon.Error);
            Environment.ExitCode = 1;
        }
    }

    public static async Task PumpInput(Stream source, Stream target)
    {
        var buffer = new byte[8192];
        int count;
        while ((count = await source.ReadAsync(buffer, 0, buffer.Length)) != 0)
        {
            await target.WriteAsync(buffer, 0, count);
            // Redirected process stdin can buffer a complete small RPC request.
            await target.FlushAsync();
        }
    }

    public static string BuildArguments(string helper, string distribution, string encodedUrl)
    {
        string arguments = "--exec " + helper + " --stdio-url-base64 " + encodedUrl + " --embed";
        if (!String.IsNullOrEmpty(distribution))
        {
            if (!Regex.IsMatch(distribution, @"^[A-Za-z0-9._-]+$"))
                throw new Exception("Invalid WSL distribution name; spaces are not supported.");
            // wsl.exe treats quotes passed through ProcessStartInfo.Arguments as
            // part of the distribution name instead of removing them.
            arguments = "--distribution " + distribution + " " + arguments;
        }
        return arguments;
    }

    public static async Task PumpOutput(Stream source, Stream target)
    {
        var prefix = new byte[8192];
        int count = 0;
        while (count < 4)
        {
            int read = await source.ReadAsync(prefix, count, prefix.Length - count);
            if (read == 0) break;
            count += read;
        }
        // WSL startup failures are UTF-16 text on stdout, not Neovim RPC.
        if (count >= 4 && prefix[0] >= 32 && prefix[1] == 0 && prefix[3] == 0)
        {
            using (var error = new MemoryStream())
            {
                error.Write(prefix, 0, count);
                await source.CopyToAsync(error);
                throw new Exception(Encoding.Unicode.GetString(error.ToArray()).Trim());
            }
        }
        // Keep the first read intact: splitting off the error-detection prefix
        // makes Neovide's handshake discard a partial RPC response.
        await target.WriteAsync(prefix, 0, count);
        await target.FlushAsync();
        await source.CopyToAsync(target);
    }

    public static void Run(string neovide, string helper, string distribution, string encodedUrl)
    {
        string name = "neovide-remote-" + Guid.NewGuid().ToString("N");
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new PipeAccessRule(
            WindowsIdentity.GetCurrent().User, PipeAccessRights.FullControl, AccessControlType.Allow));
        using (var pipe = new NamedPipeServerStream(name, PipeDirection.InOut, 1,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous, 0, 0, security))
        using (var ui = Process.Start(new ProcessStartInfo(neovide,
            "--no-fork --server \\\\.\\pipe\\" + name) { UseShellExecute = false, CreateNoWindow = true }))
        {
            var connected = pipe.BeginWaitForConnection(null, null);
            while (!connected.AsyncWaitHandle.WaitOne(100))
            {
                if (ui.HasExited) throw new Exception("Neovide exited before connecting to its RPC pipe.");
            }
            pipe.EndWaitForConnection(connected);
            // Execute the pinned helper directly: shell startup output corrupts binary RPC.
            string arguments = BuildArguments(helper, distribution, encodedUrl);
            var start = new ProcessStartInfo("wsl.exe", arguments)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var wsl = Process.Start(start))
            {
                var errors = wsl.StandardError.ReadToEndAsync();
                try
                {
                    var input = PumpInput(pipe, wsl.StandardInput.BaseStream);
                    var output = PumpOutput(wsl.StandardOutput.BaseStream, pipe);
                    int completed = Task.WaitAny(input, output);
                    (completed == 0 ? input : output).GetAwaiter().GetResult();
                    if (completed == 1 && wsl.WaitForExit(3000) && wsl.ExitCode != 0)
                        throw new Exception("WSL exited with code " + wsl.ExitCode + ": " + errors.GetAwaiter().GetResult());
                }
                finally
                {
                    pipe.Dispose();
                    wsl.StandardInput.Close();
                    if (!wsl.WaitForExit(3000)) wsl.Kill();
                    wsl.WaitForExit();
                    File.AppendAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "relay.log"),
                        DateTime.Now.ToString("o") + " WSL exit " + wsl.ExitCode + ": " +
                        errors.GetAwaiter().GetResult() + Environment.NewLine);
                }
            }
        }
    }
}
