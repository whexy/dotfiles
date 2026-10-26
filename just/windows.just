# Build the Nix Firefox config bundle and install it into Windows Firefox.
# Only works on the WSL host; requires Windows interop (powershell.exe on PATH).
firefox-windows:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d /mnt/c/Windows ]]; then
        echo "error: /mnt/c not found - this recipe must run inside WSL" >&2
        exit 1
    fi
    if ! command -v powershell.exe >/dev/null; then
        echo "error: powershell.exe not on PATH - enable WSL interop" >&2
        exit 1
    fi
    out=$(nix build .#firefox-windows-profile --no-link --print-out-paths)
    dest=/mnt/c/Windows/Temp/firefox-windows-profile
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -r "$out"/. "$dest"
    chmod -R u+w "$dest"
    echo "Installed bundle to $dest; running PowerShell installer (UAC prompt follows)..."
    powershell.exe -ExecutionPolicy Bypass -File 'C:\Windows\Temp\firefox-windows-profile\Install-FirefoxConfig.ps1'
