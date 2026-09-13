# MCP servers shared by every agent.
#
# Single source of truth for server definitions; each agent folder renders
# them into its own config format (JSON for pi and claude, inline TOML for
# codex), because no two of the three read the same file.
{
  pkgs,
  config,
  lib,
}:
let
  cfg = config.dotfiles.agents;
  firefox = config.dotfiles.browser.firefox.automation;
in
{
  servers = lib.optionalAttrs cfg.firefoxDevtools.enable {
    firefox-devtools = {
      # Not yet in the release branches; nixpkgs-unstable has it.
      command = lib.getExe pkgs.unstable.firefox-devtools-mcp;
      args = [
        # Agents run on machines with no display, and even on desktops a
        # browser window they cannot see is only a distraction.
        "--headless"
        # Keeps cookies and logins in ~/.firefox-devtools-mcp instead of a
        # fresh temporary profile per session. The server never opens the
        # user's real profile either way.
        "--auto-profile"
        # Network, console, debugger, and profiler modules on top of the
        # default preset; this is what makes the server useful for debugging
        # a page rather than only reading it.
        "--tool-preset"
        "developer"
        # BiDi otherwise applies Firefox's automation-test preferences, which
        # disable features (notably browser.ml.*) a real page may depend on.
        "--pref"
        "remote.prefs.recommended=false"
        # The desktop browser's HttpsOnlyMode policy reaches automation too: on
        # macOS policies come from the org.mozilla.firefox defaults domain,
        # which is per-user rather than per-profile, so a dedicated profile
        # does not escape it. Without this an agent cannot open the plain-HTTP
        # origins dev servers serve, and the http:// navigation fails instead
        # of showing the interstitial a human would click through.
        #
        # HttpsOnlyMode=enabled only sets the default, so a user-branch value
        # wins; it would be locked under force_enabled.
        "--pref"
        "dom.security.https_only_mode=false"
        "--pref"
        "dom.security.https_only_mode_pbm=false"
        # Auto-detection looks for a Firefox in the platform's standard
        # install location, which a Nix-installed browser is not in.
        "--firefox-path"
        firefox.binaryPath
      ];
    };
  };
}
