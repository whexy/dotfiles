# The video toolkit's skills, as a `dotfiles.agents.skills` value; the home
# module and checks/agent-skills both take it from here.
{ pkgs, perSystem, ... }:
let
  inherit (pkgs) lib;
  inherit (perSystem.self) hyperframes manimgx;
in
{
  packages = [
    hyperframes
    manimgx
  ];

  local = {
    video-edit.source = ./skills/video-edit;
    broll.source = ./skills/broll;
  };

  override =
    lib.genAttrs
      [
        "figma"
        "hyperframes"
        "hyperframes-cli"
        "hyperframes-registry"
        "media-use"
        "remotion-to-hyperframes"
        "reverse-any-video"
        "slideshow"
      ]
      (_: {
        ignore = true;
        reason = ''
          broll reads HyperFrames' skills by path, from docs.hyperframes,
          and picks the few a B-roll slot needs; listed as skills, all of
          them would crowd every session.
        '';
      })
    // {
      manimgx = {
        ignore = true;
        reason = ''
          broll reads it by path, from docs.manimgx, beside the user guide
          and examples it sends agents to.
        '';
      };
    };

  # ManimGX's tree joins its skill with the guide and examples from
  # elsewhere in its repository, so it is not a skill upstream ships.
  docs = {
    hyperframes = "${hyperframes}/share/skills";
    manimgx = manimgx.docs;
  };
}
