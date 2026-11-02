# iPhone Use for every agent: its tools drive a tailnet phone through the
# WebDriverAgent each phone runs on its own.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agenticTooling.iphoneUse;
  package = perSystem.self.iphone-wda;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    # Read by both `iphone-wda` and the MCP selector.
    home.file.".config/iphone-wda/config.json".text = builtins.toJSON {
      inherit (cfg) phones;
      wda = {
        inherit (cfg.wda) teamId bundleId;
        port = 8100;
        mjpegPort = 9100;
      };
    };

    dotfiles.agents = {
      skills = import ./skills.nix { inherit pkgs perSystem; };
      # iPhone Use behind a per-session phone choice; the tool names stay
      # iPhone Use's, so its usage skill applies unchanged.
      mcp.servers.iphone_use.command = "${package}/bin/iphone-use-select";
    };
  };
}
