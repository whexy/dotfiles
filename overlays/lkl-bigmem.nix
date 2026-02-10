# Overlay to increase LKL (Linux Kernel Library) memory from 100M to 16G
# The cptofs tool uses LKL to run a kernel as a library for filesystem operations
# during disk image creation. The default 100M causes OOM for large disk images.
# Reference: https://github.com/nix-community/nixos-generators/issues/443#issuecomment-3697547318
final: prev: {
  lkl = prev.lkl.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      # Increase LKL kernel memory for large disk image builds
      substituteInPlace tools/lkl/cptofs.c \
        --replace-fail 'lkl_start_kernel("mem=100M")' 'lkl_start_kernel("mem=16G")'
    '';
  });
}
