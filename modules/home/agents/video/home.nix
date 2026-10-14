# Video-editing toolkit. Agents cut a DaVinci Resolve timeline through
# Resolve Studio's own MCP server, which runs on the Windows host, and
# render B-roll with HyperFrames or Manim.
{ pkgs, perSystem }:
let
  inherit (perSystem.self) hyperframes;

  # browser-use/video-use (MIT) ships the Manim guide the broll skill reads.
  videoUse = pkgs.fetchFromGitHub {
    owner = "browser-use";
    repo = "video-use";
    rev = "43cfc566833548093455c9d4a46bd69913b7e552";
    hash = "sha256-sSYGBwKmH6jj/a0LHXS5IaR1TncCgAZoG5rD3BnoqDA=";
  };
in
{
  resolveMcp = perSystem.self.resolve-mcp;

  packages = [
    perSystem.self.video-edit
    hyperframes
    pkgs.manim
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
    ".local/share/video-edit/docs/manim-video".source = "${videoUse}/skills/manim-video";
    # HyperFrames' templates load GSAP from a CDN; slots copy this build
    # instead so renders work offline.
    ".local/share/video-edit/vendor/gsap.min.js".source = hyperframes.gsap;
  };
}
