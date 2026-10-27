{ pkgs }:

# DaVinci Resolve Studio's built-in MCP server: the macOS app's own, or on
# WSL the Windows program, run through interop.
#
# The server finds ResolvePython and Resolve beside itself, so it is run in
# place rather than copied. The lookup follows Blackmagic's own launcher: the
# RESOLVE_MCP_PATH override, the default install, then the registered install
# (the app for the bundle id on macOS, the one for .drp files on Windows).
#
# stdout is the MCP channel from the first byte, so every lookup is captured
# and every message goes to stderr.
let
  darwin = ''
    default="/Applications/DaVinci Resolve/DaVinci Resolve.app"
    tool=Contents/Applications/ResolveMCP

    if [[ -n "''${RESOLVE_MCP_PATH:-}" ]]; then
      exe=$RESOLVE_MCP_PATH
    elif [[ -x "$default/$tool" ]]; then
      exe=$default/$tool
    elif app=$(/usr/bin/mdfind "kMDItemCFBundleIdentifier == 'com.blackmagic-design.DaVinciResolve'" 2>/dev/null | head -n 1) &&
      [[ -n "$app" ]]; then
      exe=$app/$tool
    else
      exe=""
    fi

    if [[ -z "$exe" || ! -x "$exe" ]]; then
      echo "resolve-mcp: ResolveMCP not found''${exe:+ at $exe}." >&2
      echo "  Install DaVinci Resolve Studio, or set RESOLVE_MCP_PATH to its ResolveMCP." >&2
      exit 1
    fi

    exec "$exe" "$@"
  '';

  wsl = ''
    # shellcheck source=/dev/null
    source ${../../lib/wsl-interop.bash}

    default="/mnt/c/Program Files/Blackmagic Design/DaVinci Resolve/ResolveMCP.exe"
    drp_open='HKCR\ResolveDrpFile\shell\open\command'

    if [[ -n "''${RESOLVE_MCP_PATH:-}" ]]; then
      exe=$RESOLVE_MCP_PATH
    elif [[ -x "$default" ]]; then
      exe=$default
    elif open_command=$(win_reg_default "$drp_open"); then
      # A command line: `"C:\...\Resolve.exe" "%1"`.
      if [[ "$open_command" == \"* ]]; then
        resolve=''${open_command#\"}
        resolve=''${resolve%%\"*}
      else
        resolve=''${open_command%% *}
      fi
      exe=$(wslpath -u "''${resolve%\\*}\\ResolveMCP.exe" 2>/dev/null) || exe=""
    else
      exe=""
    fi

    if [[ -z "$exe" || ! -x "$exe" ]]; then
      echo "resolve-mcp: ResolveMCP.exe not found''${exe:+ at $exe}." >&2
      echo "  Install DaVinci Resolve Studio on Windows, or set RESOLVE_MCP_PATH to its WSL path." >&2
      exit 1
    fi

    exec "$exe" "$@"
  '';
in
pkgs.writeShellApplication {
  name = "resolve-mcp";

  text = if pkgs.stdenv.hostPlatform.isDarwin then darwin else wsl;

  meta = {
    description = "DaVinci Resolve Studio's MCP server, launched from macOS or WSL";
    platforms = pkgs.lib.platforms.linux ++ pkgs.lib.platforms.darwin;
  };
}
