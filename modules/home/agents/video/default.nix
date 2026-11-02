# Video-editing toolkit. Agents cut a DaVinci Resolve timeline through
# Resolve Studio's own MCP server, which runs beside them on macOS and on
# the Windows host under WSL, and render B-roll with HyperFrames or ManimGX.
args@{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.agents;
  inherit (perSystem.self) hyperframes manimgx;
in
{
  options.dotfiles.agents = {
    video.enable = lib.mkEnableOption "the video-editing toolkit, driving DaVinci Resolve Studio on macOS or from WSL";

    studio.enable = lib.mkOption {
      type = lib.types.bool;
      # B-roll slots take generated footage from it.
      default = cfg.video.enable;
      defaultText = lib.literalExpression "config.dotfiles.agents.video.enable";
      description = ''
        Whether to register SimpleStudio's MCP server, which generates video
        on the studio's GPU Workers. Each agent signs in to it once per
        machine, through Cloudflare Access.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            # Resolve's MCP server is the macOS app's own, or a Windows program
            # reached through WSL interop. Standalone homes have no osConfig to
            # say this is WSL.
            assertion =
              cfg.video.enable -> pkgs.stdenv.hostPlatform.isDarwin || args.osConfig.dotfiles.host.wsl or false;
            message = "dotfiles.agents.video.enable requires a macOS or WSL host.";
          }
        ];
      }

      (lib.mkIf cfg.video.enable {
        home.packages = [
          perSystem.self.video-edit
          hyperframes
          manimgx
          pkgs.ffmpeg
        ];

        # HyperFrames' templates load GSAP from a CDN; slots copy this build
        # instead so renders work offline.
        home.file.".local/share/video-edit/vendor/gsap.min.js".source = hyperframes.gsap;

        dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };

        dotfiles.agents.mcp.servers.resolve.command = lib.getExe perSystem.self.resolve-mcp;
      })

      # Cloudflare Access is the server's OAuth provider, and Studio acts as
      # the account its sign-in names, refusing the agents' service token, so
      # every agent signs the owner in itself (see AGENTS.md).
      (lib.mkIf cfg.studio.enable {
        dotfiles.agents.mcp.servers.studio = {
          type = "http";
          url = "https://studio-mcp.clusters.work/mcp";
        };
      })
    ]
  );
}
