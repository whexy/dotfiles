# Nvidia GPU support in an Incus container.
#
# The GPU is passed through on the Incus host:
#   incus config device add neith gpu gpu
#   incus config set neith nvidia.runtime=true
# The nvidia runtime bind-mounts the host driver's libraries into /usr/lib64
# and its tools (nvidia-smi, ...) into /usr/bin at instance start, so the
# container ships no driver of its own.
{ pkgs, lib, ... }:
let
  # Same shape as NixOS-WSL's wsl-lib: a store package that only points at the
  # driver the hypervisor mounts in, so the rest of NixOS can consume the
  # driver through the regular /run/opengl-driver plumbing. The links dangle
  # until the runtime mounts them, which is what makes an instance started
  # without nvidia.runtime degrade to "no GPU" instead of failing to build.
  hostDriver = pkgs.runCommand "nvidia-host-driver" { } ''
    mkdir -p "$out/etc/OpenCL/vendors"
    ln -s /usr/lib64 "$out/lib"
    echo /usr/lib64/libnvidia-opencl.so.1 > "$out/etc/OpenCL/vendors/nvidia.icd"
  '';

  # The runtime injects these into /usr/bin, which is not a NixOS path element.
  hostTools = pkgs.runCommand "nvidia-host-tools" { } ''
    mkdir -p "$out/bin"
    for tool in nvidia-smi nvidia-debugdump nvidia-persistenced \
                nvidia-cuda-mps-control nvidia-cuda-mps-server; do
      ln -s "/usr/bin/$tool" "$out/bin/$tool"
    done
  '';
in
{
  # envfs mounts a FUSE filesystem over /usr/bin after the runtime's bind
  # mounts, which would shadow the host's nvidia tools. NixOS still provides
  # the plain /usr/bin/env symlink.
  dotfiles.compat.envfs.enable = lib.mkForce false;

  # /run/opengl-driver/lib is the RUNPATH nixpkgs bakes into CUDA libraries, so
  # populating it is what lets a Nix-built libcudart find the host libcuda with
  # no environment variable at all. ocl-icd reads its vendor ICDs from the
  # matching /run/opengl-driver/etc, so OpenCL resolves the same way.
  hardware.graphics = {
    enable = true;
    # This container has no local GL stack to merge with; mesa would only add
    # a gigabyte of drivers for hardware it cannot reach.
    package = lib.mkForce hostDriver;
  };

  environment.systemPackages = [ hostTools ];

  # libcuda dlopens its JIT helpers (libnvidia-ptxjitcompiler, libnvidia-nvvm,
  # libnvidia-gpucomp) by bare soname rather than through its own RUNPATH, so
  # a driver directory reachable only via RUNPATH gets CUDA far enough to
  # enumerate devices and then fails at kernel launch. Services get no
  # /etc/set-environment, hence the separate manager default.
  systemd.settings.Manager.DefaultEnvironment = "LD_LIBRARY_PATH=/run/opengl-driver/lib";

  # nix-ld only covers unpatched binaries; Nix-built Python loading CUDA and
  # GL wheels needs the host driver and these libraries on the regular path.
  environment.sessionVariables.LD_LIBRARY_PATH = [
    "/run/current-system/sw/share/nix-ld/lib"
    "/run/opengl-driver/lib"
  ];

  programs.nix-ld.libraries = with pkgs; [
    fontconfig
    freetype
    glib
    libglvnd
    libxkbcommon
    libx11
    libxcb
    libxext
    libxrender
  ];
}
