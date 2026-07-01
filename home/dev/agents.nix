# AI coding agents configuration
{
  pkgs,
  config,
  lib,
  darwin ? false,
  ...
}:
let
  opencode_config = builtins.readFile ./opencode/config.json;
  opencode_settings = builtins.fromJSON opencode_config;
  opencode_tui_config = builtins.readFile ./opencode/tui.json;
  opencode_tui = builtins.fromJSON opencode_tui_config;

  # claude_code_config = builtins.readFile ./claude-code/settings.json;
  # claude_code_settings = builtins.fromJSON claude_code_config;
in
{
  # Deploy the OpenCode notification plugin so it is auto-loaded by OpenCode.
  home.file.".config/opencode/plugins/notify.js".source = ./opencode/plugins/notify.js;

  programs = {
    opencode = {
      enable = true;
      package = pkgs.llm-agents.opencode;
      settings = opencode_settings;
      tui = opencode_tui;
    };

    # claude-code = {
    #   enable = true;
    #   package = pkgs.llm-agents.claude-code;
    #   settings = claude_code_settings;
    # };

    # Source API keys from agenix-decrypted secret into shell environment.
    # The secret file contains KEY=VALUE lines (ANTHROPIC_API_KEY, OPENAI_API_KEY).
    #
    # Agenix decrypts secrets to ${XDG_RUNTIME_DIR}/agenix/ by default.
    #
    # 1. Special handling for mosh over ssh
    # On Linux, XDG_RUNTIME_DIR is set by pam_systemd during login, and
    # systemd user services always have it (inherited from the user manager).
    # However, mosh shells may lack it: mosh-server detaches from the
    # original SSH session, and reconnections don't trigger a new PAM session.
    # On systemd-based Linux, /run/user/<UID> is guaranteed to exist, so we use it
    # as a safe fallback.
    #
    # 2. Special handling for macOS
    # On macOS, XDG_RUNTIME_DIR doesn't apply (/run/user/ doesn't exist);
    # the agenix HM module uses $TMPDIR internally, so no fallback is needed.
    #
    # 3. Special handling for WSL
    # Use initContent (.zshrc) instead of envExtra (.zshenv) to avoid a race
    # condition on WSL: shell-wrapper spawns the first zsh simultaneously with
    # agenix.service, so the secret file may not exist yet when .zshenv runs.
    # Interactive shells (the only consumers of these keys) always open after
    # the systemd user session is fully up, so .zshrc is safe.
    zsh.initContent = lib.mkAfter ''
      ${lib.optionalString (!darwin) ''
        if [ -z "$XDG_RUNTIME_DIR" ]; then
          export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        fi
      ''}
      if [ -f "${config.age.secrets.api-keys.path}" ]; then
        set -a
        source "${config.age.secrets.api-keys.path}"
        set +a
      fi
    '';
  };
}
