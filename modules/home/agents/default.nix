# AI coding agents: Claude Code, Codex, OpenCode, and Muse Code, with the
# rules, skills, and MCP servers every one of them shares.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
{
  imports = [
    ./launcher/default.nix
    ./mcp.nix
    ./skill-tree/default.nix
    ./claude-code/default.nix
    ./codex/default.nix
    ./opencode/default.nix
    ./muse-code/default.nix
  ];

  options.dotfiles.agents.enable = lib.mkEnableOption "agents";

  # Adding a skill is a new directory under ./skills, never a change here.
  config = lib.mkIf config.dotfiles.agents.enable {
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };
    age.secrets = config.dotfiles.llmGateways.secrets;
  };
}
