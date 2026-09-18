<#
.SYNOPSIS
  Installs the Nix-generated Firefox configuration into Windows Firefox.

.DESCRIPTION
  Copies the files sitting next to this script:

    user.js               -> every profile in %APPDATA%\Mozilla\Firefox\Profiles
    chrome/userChrome.css -> <profile>\chrome\userChrome.css
    policies.json         -> <Firefox install dir>\distribution\policies.json

  policies.json lives in the Firefox installation directory, which requires
  administrator rights, so the script re-launches itself elevated. Restart
  Firefox afterwards for everything to take effect.
#>
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $MyInvocation.MyCommand.Path

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal] $identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host 'Elevation required for policies.json - restarting as administrator...'
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    exit
}

if (Get-Process firefox -ErrorAction SilentlyContinue) {
    Write-Warning 'Firefox is running; the new settings only apply after a full restart.'
}

# --- Per-profile files -------------------------------------------------------
$profilesRoot = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
if (-not (Test-Path $profilesRoot)) {
    throw "No Firefox profiles found at $profilesRoot. Start Firefox once, then re-run."
}

foreach ($profile in Get-ChildItem $profilesRoot -Directory) {
    Copy-Item (Join-Path $src 'user.js') (Join-Path $profile.FullName 'user.js') -Force
    $chromeDir = Join-Path $profile.FullName 'chrome'
    New-Item -ItemType Directory -Force -Path $chromeDir | Out-Null
    Copy-Item (Join-Path $src 'chrome\userChrome.css') (Join-Path $chromeDir 'userChrome.css') -Force
    Write-Host "Updated profile: $($profile.Name)"
}

# --- policies.json -----------------------------------------------------------
$installDir = @(
    (Join-Path $env:ProgramFiles 'Mozilla Firefox'),
    (Join-Path ${env:ProgramFiles(x86)} 'Mozilla Firefox')
) | Where-Object { Test-Path (Join-Path $_ 'firefox.exe') } | Select-Object -First 1

if (-not $installDir) {
    Write-Warning 'Firefox installation not found under Program Files; skipping policies.json.'
}
else {
    $distDir = Join-Path $installDir 'distribution'
    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    Copy-Item (Join-Path $src 'policies.json') (Join-Path $distDir 'policies.json') -Force
    Write-Host "Installed policies.json -> $distDir"
}

Write-Host 'Done. Restart Firefox to apply.'
