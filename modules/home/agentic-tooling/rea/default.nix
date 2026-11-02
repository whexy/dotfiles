# REA, the reverse-engineering MCP server and CLI, with the engines enabled
# here baked into its wrapper.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agenticTooling.rea;
  rea = import ./engines.nix {
    inherit
      pkgs
      lib
      cfg
      perSystem
      ;
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ rea.package ];
    home.sessionVariables = rea.sessionVariables;
    dotfiles.agents = {
      skills = import ./skills.nix { inherit pkgs perSystem; };
      # Registered here rather than by `rea setup`, which would write an
      # npx-pinned entry into every agent's own config.
      mcp.servers.rea = {
        command = lib.getExe rea.package;
        args = [ "mcp" ];
      };
    };
  };
}
