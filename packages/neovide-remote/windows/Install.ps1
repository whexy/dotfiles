param([string]$Neovide = 'neovide.exe', [string]$Helper = 'neovide-remote', [string]$Distribution = '')
if ($Helper -notmatch '^[A-Za-z0-9/._+-]+$') { throw 'Invalid WSL helper path.' }
$ErrorActionPreference = 'Stop'
$exe = (Get-Command $Neovide -CommandType Application -ErrorAction Stop).Source
$destination = Join-Path $env:LOCALAPPDATA 'NeovideRemote'
New-Item -ItemType Directory -Force $destination | Out-Null
$source = Get-Content -Raw (Join-Path $PSScriptRoot 'Relay.cs')
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
    $digest = [BitConverter]::ToString($sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($source))).Replace('-', '').ToLowerInvariant()
} finally {
    $sha256.Dispose()
}
# Windows locks running executables; each source version gets its own launcher.
$launcher = Join-Path $destination "NeovideRemote-$digest.exe"
if (!(Test-Path $launcher)) {
    Add-Type -TypeDefinition $source -OutputAssembly $launcher -OutputType WindowsApplication -ReferencedAssemblies @('System.dll', 'System.Core.dll', 'System.Xml.dll', 'System.Windows.Forms.dll')
}
$config = [xml]'<Configuration><Neovide/><Helper/><Distribution/></Configuration>'
$config.Configuration.Neovide = $exe
$config.Configuration.Helper = $Helper
$config.Configuration.Distribution = $Distribution
$config.Save((Join-Path $destination 'config.xml'))
$command = "`"$launcher`" `"%1`""
foreach ($class in @('vscode', 'NeovideRemote.Url')) {
    $key = "HKCU:\Software\Classes\$class"
    New-Item -Force $key | Out-Null
    Set-Item $key -Value 'URL:Neovide Remote'
    New-ItemProperty -Path $key -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
    New-Item -Force "$key\shell\open\command" | Out-Null
    Set-Item "$key\shell\open\command" -Value $command
}
$capabilities = 'HKCU:\Software\NeovideRemote\Capabilities'
New-Item -Force $capabilities | Out-Null
New-ItemProperty $capabilities -Name ApplicationName -Value 'Neovide Remote' -Force | Out-Null
New-ItemProperty $capabilities -Name ApplicationDescription -Value 'Open SSH remote links in Neovide through WSL' -Force | Out-Null
New-Item -Force "$capabilities\URLAssociations" | Out-Null
New-ItemProperty "$capabilities\URLAssociations" -Name vscode -Value 'NeovideRemote.Url' -Force | Out-Null
New-Item -Force 'HKCU:\Software\RegisteredApplications' | Out-Null
New-ItemProperty 'HKCU:\Software\RegisteredApplications' -Name 'Neovide Remote' -Value 'Software\NeovideRemote\Capabilities' -Force | Out-Null
Write-Host "Registered vscode:// for $exe (current user). WSL distribution: $Distribution (empty means default)."
Write-Host 'If links still open VS Code, select Neovide Remote for VSCODE in Windows Settings > Apps > Default apps.'
