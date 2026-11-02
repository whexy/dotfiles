# iPhone Use for every agent: its tools drive a tailnet phone through the
# WebDriverAgent each phone runs on its own.
{
  config,
  lib,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agents.iphoneUse;
  package = perSystem.self.iphone-wda;
in
{
  options.dotfiles.agents.iphoneUse = {
    enable = lib.mkEnableOption ''
      iPhone Use for every agent: its tools drive one of `phones`, chosen
      by the user per session, through the WebDriverAgent each phone runs
      on its Tailscale address
    '';
    phones = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              description = "The phone's MagicDNS name.";
            };
            deviceName = lib.mkOption {
              type = lib.types.str;
              description = "The name set on the phone, which `iphone-wda` finds it by on a paired Mac.";
            };
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "What the agent shows the user when asking which phone to use.";
            };
          };
        }
      );
      default = import ./phones.nix;
      defaultText = lib.literalExpression "import ./phones.nix";
      description = "The iPhones agents can drive, by the name the agent shows.";
    };
    wda = {
      teamId = lib.mkOption {
        type = lib.types.str;
        default = "26DMRHRW6Z";
        description = "Apple development team that signs WebDriverAgent.";
      };
      bundleId = lib.mkOption {
        type = lib.types.str;
        default = "dev.whexy.iphoneuse.wda";
        description = "WebDriverAgent's bundle ID; the runner installs as `<bundleId>.xctrunner`.";
      };
    };
  };

  config = lib.mkIf (config.dotfiles.agents.enable && cfg.enable) {
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

    dotfiles.agents.skills = import ./skills.nix { iphoneUse = perSystem.self.iphone-use; };

    # iPhone Use behind a per-session phone choice; the tool names stay
    # iPhone Use's, so its usage skill applies unchanged.
    dotfiles.agents.mcp.servers.iphone_use.command = "${package}/bin/iphone-use-select";
  };
}
