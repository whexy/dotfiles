# Provide a tailscale-wsl package whose `tailscale` command is the Windows
# client's CLI. WSL shares the Windows host's network stack, so the node is
# owned by Windows and a Linux-side tailscaled would only add a second one.
#
# Note: this is a SEPARATE package (tailscale-wsl), not an override of
# `tailscale`, so the real package stays available for anything that needs the
# daemon or its NixOS module.
_final: prev: {
  tailscale-wsl = prev.writeShellScriptBin "tailscale" ''
    set -euo pipefail

    CACHE_FILE="''${XDG_CACHE_HOME:-$HOME/.cache}/tailscale-wsl/tailscale-exe-path"

    # Try cached path first
    if [[ -f "$CACHE_FILE" ]]; then
      CACHED_PATH=$(<"$CACHE_FILE")
      if [[ -x "$CACHED_PATH" ]]; then
        exec "$CACHED_PATH" "$@"
      fi
      # Cache invalid, remove it
      rm -f "$CACHE_FILE"
    fi

    # Search for tailscale.exe
    TS_EXE=""

    # Method 1: PATH (the Windows installer adds its directory to the system PATH)
    TS_EXE=$(command -v tailscale.exe 2>/dev/null) || true

    # Method 2: the default install location under Program Files
    if [[ -z "$TS_EXE" ]] || [[ ! -x "$TS_EXE" ]]; then
      PROGRAM_FILES=$(wslpath "$(cmd.exe /c 'echo %ProgramFiles%' 2>/dev/null | tr -d '\r\n')" 2>/dev/null) || true
      if [[ -n "$PROGRAM_FILES" ]] && [[ -x "$PROGRAM_FILES/Tailscale/tailscale.exe" ]]; then
        TS_EXE="$PROGRAM_FILES/Tailscale/tailscale.exe"
      fi
    fi

    # Fail if not found
    if [[ -z "$TS_EXE" ]] || [[ ! -x "$TS_EXE" ]]; then
      echo "Error: tailscale.exe not found. Install Tailscale on Windows:" >&2
      echo "  winget install tailscale.tailscale" >&2
      exit 1
    fi

    # Cache the path for next time
    mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$TS_EXE" > "$CACHE_FILE"

    exec "$TS_EXE" "$@"
  '';
}
