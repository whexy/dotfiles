# AI coding agents: Claude Code, Codex, OpenCode, and Muse Code, with the
# rules, skills, and MCP servers every one of them shares.
{
  config,
  lib,
  perSystem,
  ...
}:
{
  imports = [
    ./launcher/default.nix
    ./llm-gateways.nix
    ./mcp.nix
    ./skill-tree/default.nix
    ./tunnels.nix
    ./claude-code/default.nix
    ./codex/default.nix
    ./opencode/default.nix
    ./muse-code/default.nix
    ./t3code/default.nix
    ./firefox-devtools.nix
    ./rea/default.nix
    ./video/default.nix
    ./iphone/default.nix
    ./spark/default.nix
    ./asc/default.nix
    ./cloudflare/default.nix
  ];

  options.dotfiles.agents.enable = lib.mkEnableOption "agents";

  config = lib.mkIf config.dotfiles.agents.enable {
    # CLIs that shared skills drive; every harness reaches them through PATH.
    home.packages = [
      # whisper-1 needs an OpenAI key in the environment of this process
      # alone; the store and the agent that runs it never see the key.
      (config.dotfiles.onepassword.wrap {
        package = perSystem.self.transcribe;
        env.OPENAI_API_KEY = "openai-api-key";
      })
      perSystem.self.wechat-cli
    ];

    dotfiles.agents.skills = {
      packages = [
        perSystem.self.transcribe
        perSystem.self.wechat-cli
      ];
      # Adding a skill is a new directory under ./skills, never a change here.
      local = lib.mapAttrs (name: _: { source = ./skills + "/${name}"; }) (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./skills)
      );
    };
  };
}
