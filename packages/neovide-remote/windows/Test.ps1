param([Parameter(Mandatory = $true)][string]$Url)
$ErrorActionPreference = 'Stop'
$config = [xml](Get-Content (Join-Path $env:LOCALAPPDATA 'NeovideRemote\config.xml'))
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('neovide-relay-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temporary | Out-Null
try {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $test = Join-Path $temporary 'TestRelay.exe'
    & $compiler /nologo /target:exe /main:TestRelay /reference:System.Windows.Forms.dll "/out:$test" (Join-Path $PSScriptRoot 'Relay.cs') (Join-Path $PSScriptRoot 'TestRelay.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Windows relay test compilation failed.' }
    & $test $config.Configuration.Helper $Url $config.Configuration.Distribution
    if ($LASTEXITCODE -ne 0) { throw 'Windows relay tests failed.' }
} finally {
    Remove-Item -Recurse -Force $temporary
}
