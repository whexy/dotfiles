using System;
using System.IO;
using System.Diagnostics;
using System.Threading.Tasks;
using System.Linq;
public class TestRelay {
    private class RecordingStream : MemoryStream {
        public int Writes;
        public override Task WriteAsync(byte[] buffer, int offset, int count, System.Threading.CancellationToken cancellationToken) {
            Writes++;
            return base.WriteAsync(buffer, offset, count, cancellationToken);
        }
    }
    public static void Main(string[] commandLine) {
        if (commandLine.Length > 0 && commandLine[0] == "--echo") {
            Console.OpenStandardInput().CopyTo(Console.OpenStandardOutput());
            return;
        }
        string args = NeovideRemoteRelay.BuildArguments("/nix/store/test/bin/neovide-remote", "NixOS", "dGVzdA==");
        if (args != "--distribution NixOS --exec /nix/store/test/bin/neovide-remote --stdio-url-base64 dGVzdA== --embed")
            throw new Exception("Distribution argument quoting is incorrect: " + args);
        try {
            NeovideRemoteRelay.BuildArguments("/nix/store/test/bin/neovide-remote", "Nix OS", "dGVzdA==");
            throw new Exception("Distribution names with spaces were accepted");
        } catch (Exception error) {
            if (error.Message != "Invalid WSL distribution name; spaces are not supported.") throw;
        }
        var destination = new RecordingStream();
        try {
            NeovideRemoteRelay.PumpOutput(new MemoryStream(System.Text.Encoding.Unicode.GetBytes("WSL_E_DISTRO_NOT_FOUND")), destination).GetAwaiter().GetResult();
            throw new Exception("WSL error was forwarded as RPC");
        } catch (Exception error) {
            if (error.Message != "WSL_E_DISTRO_NOT_FOUND" || destination.Length != 0) throw;
        }
        var packet = new byte[] { 0x94, 1, 0, 0xc0, 0xd9, 36 }
            .Concat(System.Text.Encoding.UTF8.GetBytes("NeovideToNeovimMagicHandshakeMessage")).ToArray();
        NeovideRemoteRelay.PumpOutput(new MemoryStream(packet), destination).Wait();
        if (!System.Linq.Enumerable.SequenceEqual(packet, destination.ToArray())) throw new Exception("RPC output changed");
        if (destination.Writes != 1) throw new Exception("The first RPC response was fragmented at the error-detection prefix");
        bool windows = Environment.OSVersion.Platform == PlatformID.Win32NT;
        if (windows) {
            if (commandLine.Length < 2 || commandLine.Length > 3) throw new Exception("Expected pinned helper path, SSH remote URL, and optional WSL distribution");
            string distribution = commandLine.Length == 3 ? commandLine[2] : "";
            string url = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(commandLine[1]));
            var start = new ProcessStartInfo("wsl.exe", NeovideRemoteRelay.BuildArguments(commandLine[0], distribution, url)) {
                UseShellExecute=false, CreateNoWindow=true, RedirectStandardInput=true,
                RedirectStandardOutput=true, RedirectStandardError=true
            };
            using (var process = Process.Start(start)) {
                var errors = process.StandardError.ReadToEndAsync();
                try {
                    byte[] request = new byte[] { 0x94, 0, 1, 0xa9, 110, 118, 105, 109, 95, 101, 118, 97, 108, 0x91, 0xa3, 54, 42, 55 };
                    process.StandardInput.BaseStream.Write(request, 0, request.Length);
                    process.StandardInput.BaseStream.Flush();
                    var reply = new byte[5];
                    int count = 0;
                    while (count < reply.Length) {
                        var read = process.StandardOutput.BaseStream.ReadAsync(reply, count, reply.Length - count);
                        if (!read.Wait(15000)) throw new Exception("Pinned WSL helper RPC timed out");
                        if (read.Result == 0) throw new Exception("Pinned WSL helper closed stdout: " + errors.GetAwaiter().GetResult());
                        count += read.Result;
                    }
                    if (!System.Linq.Enumerable.SequenceEqual(reply, new byte[] { 0x94, 1, 1, 0xc0, 42 }))
                        throw new Exception("Pinned WSL helper did not return binary RPC: " + BitConverter.ToString(reply));
                    Console.WriteLine("Windows WSL argv and pinned helper binary RPC passed");
                } finally {
                    process.StandardInput.Close();
                    if (!process.WaitForExit(3000)) process.Kill();
                    process.WaitForExit();
                }
                if (process.ExitCode != 0) throw new Exception("WSL helper did not exit cleanly: " + errors.GetAwaiter().GetResult());
            }
        }
        string executable = windows ? System.Reflection.Assembly.GetExecutingAssembly().Location : "cat";
        using (var process = Process.Start(new ProcessStartInfo(executable, windows ? "--echo" : "") { UseShellExecute=false, CreateNoWindow=true, RedirectStandardInput=true, RedirectStandardOutput=true })) {
            try {
                var target = new BufferedStream(process.StandardInput.BaseStream, 4096);
                NeovideRemoteRelay.PumpInput(new MemoryStream(new byte[] { 0x94, 0x00, 0x01 }), target).Wait();
                byte[] reply = new byte[3];
                var read = process.StandardOutput.BaseStream.ReadAsync(reply, 0, 3);
                if (!read.Wait(3000) || read.Result != 3 || reply[0] != 0x94) throw new Exception("Small RPC packet was buffered");
                Console.WriteLine("Small RPC request flushed before stdin closes");
            } finally { process.Kill(); process.WaitForExit(); }
        }
    }
}
