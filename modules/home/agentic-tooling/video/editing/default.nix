# Video editing: agents cut a DaVinci Resolve timeline through Resolve
# Studio's own MCP server, which runs beside them on macOS and on the
# Windows host under WSL. B-roll slots are filled by video making.
args@{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agenticTooling.video;
in
{
  config = lib.mkIf cfg.editing.enable {
    assertions = [
      {
        # Resolve's MCP server is the macOS app's own, or a Windows program
        # reached through WSL interop. Standalone homes have no osConfig to
        # say this is WSL.
        assertion = pkgs.stdenv.hostPlatform.isDarwin || args.osConfig.dotfiles.host.wsl or false;
        message = "dotfiles.agenticTooling.video.editing.enable requires a macOS or WSL host.";
      }
      {
        assertion = cfg.making.enable;
        message = "dotfiles.agenticTooling.video.editing.enable needs video.making.enable, which renders its B-roll and installs video-edit.";
      }
    ];

    dotfiles.agents = {
      skills = import ./skills.nix { };
      mcp.servers.resolve.command = lib.getExe perSystem.self.resolve-mcp;
    };
  };
}
