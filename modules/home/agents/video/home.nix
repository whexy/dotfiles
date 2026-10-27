# Video-editing toolkit. Agents cut a DaVinci Resolve timeline through
# Resolve Studio's own MCP server, which runs beside them on macOS and on
# the Windows host under WSL, and render B-roll with HyperFrames or ManimGX.
{ pkgs, perSystem }:
let
  inherit (perSystem.self) hyperframes manimgx;
in
{
  resolveMcp = perSystem.self.resolve-mcp;

  packages = [
    perSystem.self.video-edit
    hyperframes
    manimgx
    pkgs.ffmpeg
  ];

  skills = {
    video-edit = ./skills/video-edit;
    broll = ./skills/broll;
  };

  # Engine guides are read by path from the broll skill instead of being
  # registered as skills: HyperFrames alone has 21, which every session would
  # otherwise list.
  homeFiles = {
    ".local/share/video-edit/docs/hyperframes".source = hyperframes.skills;
    ".local/share/video-edit/docs/manimgx".source = manimgx.docs;
    # HyperFrames' templates load GSAP from a CDN; slots copy this build
    # instead so renders work offline.
    ".local/share/video-edit/vendor/gsap.min.js".source = hyperframes.gsap;
  };
}
