# AI coding agents configuration
{
  pkgs,
  config,
  lib,
  ...
}:
{
  home.packages = with pkgs.llm-agents; [
    opencode
    claude-code
  ];

  # Source API keys from agenix-decrypted secret into shell environment.
  # The secret file contains KEY=VALUE lines (ANTHROPIC_API_KEY, OPENAI_API_KEY).
  #
  # Agenix decrypts secrets to ${XDG_RUNTIME_DIR}/agenix/ by default.
  # XDG_RUNTIME_DIR is set by pam_systemd during login, and systemd user
  # services always have it (inherited from the user manager). However,
  # mosh shells may lack it: mosh-server detaches from the original SSH
  # session, and reconnections don't trigger a new PAM session.
  # Since mosh is only enabled on NixOS (systemd-based), /run/user/<UID>
  # is guaranteed to exist, so we use it as a safe fallback.
  #
  # Use initContent (.zshrc) instead of envExtra (.zshenv) to avoid a race
  # condition on WSL: shell-wrapper spawns the first zsh simultaneously with
  # agenix.service, so the secret file may not exist yet when .zshenv runs.
  # Interactive shells (the only consumers of these keys) always open after
  # the systemd user session is fully up, so .zshrc is safe.
  programs.zsh.initContent = lib.mkAfter ''
    if [ -z "$XDG_RUNTIME_DIR" ]; then
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    fi
    if [ -f "${config.age.secrets.api-keys.path}" ]; then
      set -a
      source "${config.age.secrets.api-keys.path}"
      set +a
    fi
  '';
}
