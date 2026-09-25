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
  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # Keep the desktop browser's force-installed extensions out of automation.
  #
  # The policy engine installs them into the profile regardless of the profile
  # or the extension scope prefs, and on macOS the policies come from the
  # per-user org.mozilla.firefox defaults domain, so a dedicated profile does
  # not escape them. They then open their own onboarding tabs, which an agent
  # has to read past on every session.
  #
  # Firefox reads that domain through NSUserDefaults, whose search list puts a
  # process's own argv (the argument domain) ahead of the persisted one, so an
  # -ExtensionSettings pair on the command line masks the stored value for
  # that launch alone and writes nothing. Firefox itself does not recognise
  # the flag and logs a warning; Cocoa consumes it before Firefox parses argv.
  #
  # Only ExtensionSettings is masked, so the remaining policies (tracking
  # protection, telemetry, suggest) still apply. Disabling the whole engine
  # with -EnterprisePoliciesEnabled NO would drop those too, which is why the
  # HttpsOnlyMode prefs below are still needed.
  #
  # The value has to reach Firefox as a string: the server's argument parser
  # coerces a bare 0/1 to a number and then fails on a non-string argv entry.
  # The --firefoxArg=-Foo form is likewise required, or the parser claims the
  # leading dash as one of its own options.
  #
  # Cocoa-only. On Linux these policies arrive through the wrapped package's
  # policies.json instead, where there is no argument domain to override.
  unpolicedExtensions = lib.optionals isDarwin [
    "--firefoxArg=-ExtensionSettings"
    "--firefoxArg={}"
  ];
in
{
  servers = {
    # n8n workflow that reaches the user away from the desk: phone push,
    # WeChat, and a Slack note-to-self. It has no authentication.
    #
    # `type` is Claude's discriminator for a remote server; codex and
    # pi-mcp-adapter key on `url` and ignore it.
    personal = {
      type = "http";
      url = "https://n8n.clusters.work/mcp/3e3dc609-1939-47ed-94ef-964a3164dfae";
    };
  }
  // lib.optionalAttrs cfg.firefoxDevtools.enable {
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
      ]
      ++ unpolicedExtensions;
    };
  };
}
