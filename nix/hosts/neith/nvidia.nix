# Nvidia GPU support in an Incus container.
#
# The GPU is passed through on the Incus host:
#   incus config device add neith gpu gpu
#   incus config set neith nvidia.runtime=true
# The nvidia runtime bind-mounts the host driver's libraries into /usr/lib64
# and its tools (nvidia-smi, ...) into /usr/bin at instance start, so the
# container ships no driver of its own.
{ pkgs, lib, ... }:
{
  # envfs mounts a FUSE filesystem over /usr/bin after the runtime's bind
  # mounts, which would shadow the host's nvidia tools. NixOS still provides
  # the plain /usr/bin/env symlink.
  dotfiles.compat.envfs.enable = lib.mkForce false;

  # nix-ld only covers unpatched binaries; Nix-built Python loading CUDA and
  # GL wheels needs the host driver and these libraries on the regular path.
  environment.sessionVariables.LD_LIBRARY_PATH = [
    "/run/current-system/sw/share/nix-ld/lib"
    "/usr/lib64"
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
