{ pkgs }:

# Mesa's Dozen (Vulkan on D3D12), the GPU's only Vulkan driver on WSL,
# patched so wgpu takes it. Built alone: no other Mesa driver is needed.
let
  inherit (pkgs) lib;
in
pkgs.mesa.overrideAttrs (old: {
  pname = "mesa-dzn";
  patches = old.patches ++ [ ./dzn.patch ];
  outputs = [ "out" ];
  # nixpkgs enables every auto feature, which needs the drivers left out.
  mesonAutoFeatures = "auto";
  mesonFlags = [
    "--sysconfdir=/etc"
    (lib.mesonOption "platforms" "")
    (lib.mesonOption "gallium-drivers" "")
    (lib.mesonOption "vulkan-drivers" "microsoft-experimental")
    (lib.mesonOption "vulkan-layers" "")
    (lib.mesonBool "opengl" false)
    (lib.mesonEnable "glx" false)
    (lib.mesonEnable "egl" false)
    (lib.mesonEnable "gbm" false)
    (lib.mesonEnable "glvnd" false)
    (lib.mesonEnable "gles1" false)
    (lib.mesonEnable "gles2" false)
    (lib.mesonEnable "llvm" false)
    (lib.mesonEnable "valgrind" false)
    (lib.mesonOption "video-codecs" "")
  ];
  postInstall = "";
  postFixup = "";
})
