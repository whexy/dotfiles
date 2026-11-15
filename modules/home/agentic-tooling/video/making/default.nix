# Video making: agents render B-roll with HyperFrames or ManimGX, or take
# generated footage from Studio, and finalize it with video-edit, on the GPU
# dotfiles.hardware.gpu labels.
{
  config,
  lib,
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  cfg = config.dotfiles.agenticTooling.video;
  gpu = config.dotfiles.hardware.gpu;
  inherit (perSystem.self) hyperframes manimgx video-edit;

  # A GPU without an encoder (NVIDIA's A100) still draws; finals then
  # encode on the CPU.
  encoder =
    if gpu.videoEncoder then
      {
        amd = "hevc_vaapi";
        apple = "hevc_videotoolbox";
        nvidia = "hevc_nvenc";
      }
      .${gpu.vendor}
    else
      "libx265";

  gpuArgs =
    lib.optionals (gpu.libraryPath != [ ]) [
      "--prefix"
      "LD_LIBRARY_PATH"
      ":"
      (lib.concatStringsSep ":" gpu.libraryPath)
    ]
    ++ lib.concatLists (
      lib.mapAttrsToList (name: value: [
        "--set-default"
        name
        value
      ]) gpu.environment
    );

  onGpu =
    extraArgs: pkg:
    pkgs.symlinkJoin {
      inherit (pkg) name meta;
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for program in "$out"/bin/*; do
          wrapProgram "$program" ${lib.escapeShellArgs (gpuArgs ++ extraArgs)}
        done
      '';
    };
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.making.enable {
      home.packages = [
        (onGpu [ "--set-default" "VIDEO_EDIT_ENCODER" encoder ] video-edit)
        (onGpu [ ] hyperframes)
        (onGpu [ ] manimgx)
        pkgs.ffmpeg
      ];

      # HyperFrames' templates load GSAP from a CDN; slots copy this build
      # instead so renders work offline.
      home.file.".local/share/video-edit/vendor/gsap.min.js".source = hyperframes.gsap;

      dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem flake; };
    })

    # Cloudflare Access is the server's OAuth provider, and Studio acts as
    # the account its sign-in names, refusing the agents' service token, so
    # every agent signs the owner in itself (see AGENTS.md).
    (lib.mkIf cfg.studio.enable {
      dotfiles.agents.mcp.servers.studio.url = "https://studio-mcp.clusters.work/mcp";
    })
  ];
}
