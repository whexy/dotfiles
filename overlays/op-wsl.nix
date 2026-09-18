# Override 1password-cli to use Windows op.exe in WSL
# Dynamically locates op.exe via WinGet or PATH, with caching for performance
_final: prev: {
  _1password-cli = prev.writeShellScriptBin "op" ''
    set -euo pipefail

    CACHE_FILE="''${XDG_CACHE_HOME:-$HOME/.cache}/op-wsl/op-exe-path"

    # Try cached path first
    if [[ -f "$CACHE_FILE" ]]; then
      CACHED_PATH=$(<"$CACHE_FILE")
      if [[ -x "$CACHED_PATH" ]]; then
        exec "$CACHED_PATH" "$@"
      fi
      # Cache invalid, remove it
      rm -f "$CACHE_FILE"
    fi

    # Search for op.exe
    OP_EXE=""

    # Method 1: WinGet packages (most common)
    if [[ -z "$OP_EXE" ]]; then
      LOCALAPPDATA=$(wslpath "$(cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | tr -d '\r\n')" 2>/dev/null) || true
      if [[ -n "$LOCALAPPDATA" ]]; then
        WINGET_PKGS="$LOCALAPPDATA/Microsoft/WinGet/Packages"
        OP_EXE=$(find "$WINGET_PKGS" -maxdepth 2 -name "op.exe" -type f 2>/dev/null | head -1) || true
      fi
    fi

    # Method 2: Fall back to PATH (for other install methods)
    if [[ -z "$OP_EXE" ]] || [[ ! -x "$OP_EXE" ]]; then
      OP_EXE=$(command -v op.exe 2>/dev/null) || true
    fi

    # Fail if not found
    if [[ -z "$OP_EXE" ]] || [[ ! -x "$OP_EXE" ]]; then
      echo "Error: op.exe not found. Install 1Password CLI on Windows:" >&2
      echo "  winget install AgileBits.1Password.CLI" >&2
      exit 1
    fi

    # Cache the path for next time
    mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$OP_EXE" > "$CACHE_FILE"

    exec "$OP_EXE" "$@"
  '';
}
