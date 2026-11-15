# The machine's GPU, as the system labels it in dotfiles.hardware.gpu.
# Standalone homes have no osConfig and label their own.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  os = if osConfig != null then osConfig.dotfiles.hardware.gpu else null;
  cfg = config.dotfiles.hardware.gpu;
  fromOs =
    name: fallback: defaultText:
    lib.mkOption {
      default = if os != null then os.${name} else fallback;
      defaultText = lib.literalExpression "osConfig.dotfiles.hardware.gpu.${name}, or ${defaultText} without osConfig";
      inherit (specs.${name}) type description;
    };
  specs = {
    vendor = {
      type = lib.types.nullOr (
        lib.types.enum [
          "amd"
          "apple"
          "nvidia"
        ]
      );
      description = "The vendor of the GPU that programs here draw and encode video on; null without one.";
    };
    videoEncoder = {
      type = lib.types.bool;
      description = "Whether that GPU has a hardware video encoder; NVIDIA's A100 has none.";
    };
    libraryPath = {
      type = lib.types.listOf lib.types.str;
      description = "Library directories a Nix program needs on LD_LIBRARY_PATH to reach the GPU's driver.";
    };
    environment = {
      type = lib.types.attrsOf lib.types.str;
      description = "Variables that steer a program onto that GPU.";
    };
  };

  # A distribution's NVIDIA driver sits among all its other libraries, and
  # a Nix program reads no ld.so.cache to find it.
  driverLib = "${config.xdg.stateHome}/host-gpu-driver/lib";
  distroLib = [
    "/usr/lib/${pkgs.stdenv.hostPlatform.parsed.cpu.name}-linux-gnu"
    "/usr/lib64"
  ];
in
{
  options.dotfiles.hardware.gpu = {
    vendor = fromOs "vendor" null "null";
    videoEncoder = fromOs "videoEncoder" (cfg.vendor != null) "vendor != null";
    libraryPath = fromOs "libraryPath" [ ] "[ ]";
    environment = fromOs "environment" { } "{ }";
  };

  config = lib.mkIf (osConfig == null && cfg.vendor == "nvidia" && pkgs.stdenv.hostPlatform.isLinux) {
    # libGLX_nvidia, which serves Vulkan, also links X11 and loads the EGL
    # dispatcher, which must be Nix's.
    dotfiles.hardware.gpu.libraryPath = [
      driverLib
    ]
    ++ map (pkg: "${lib.getLib pkg}/lib") [
      pkgs.libglvnd
      pkgs.libx11
      pkgs.libxext
    ];

    # Links only the driver's libraries, again on every switch: a driver
    # upgrade renames the versioned ones.
    home.activation.hostGpuDriver = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      driverLib=${lib.escapeShellArg driverLib}
      run rm -rf "$driverLib"
      run mkdir -p "$driverLib"
      found=
      for dir in ${lib.escapeShellArgs distroLib}; do
        for so in "$dir"/lib{cuda,nvcuvid,GLX_nvidia,EGL_nvidia,nvidia-}*.so*; do
          [ -e "$so" ] || continue
          run ln -s "$so" "$driverLib/"
          found=1
        done
        [ -n "$found" ] && break
      done
      [ -n "$found" ] || warnEcho "No NVIDIA driver libraries in ${lib.concatStringsSep " or " distroLib}."
    '';
  };
}
