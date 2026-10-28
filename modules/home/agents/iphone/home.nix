{
  cfg,
  perSystem,
}:
let
  package = perSystem.self.iphone-wda;
in
{
  packages = [ package ];

  # Read by both `iphone-wda` and the MCP selector.
  homeFiles.".config/iphone-wda/config.json".text = builtins.toJSON {
    inherit (cfg) phones;
    wda = {
      inherit (cfg.wda) teamId bundleId;
      port = 8100;
      mjpegPort = 9100;
    };
  };
}
