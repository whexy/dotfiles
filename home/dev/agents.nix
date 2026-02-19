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

  # Source API keys from agenix-decrypted secret into shell environment
  # The secret file contains KEY=VALUE lines (ANTHROPIC_API_KEY, OPENAI_API_KEY)
  programs.zsh.initContent = lib.mkAfter ''
    if [ -f "${config.age.secrets.api-keys.path}" ]; then
      set -a
      source "${config.age.secrets.api-keys.path}"
      set +a
    fi
  '';
}
