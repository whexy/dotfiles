{ pkgs }:
let
  inherit (pkgs) lib;
in
# tsnet's module requires the Go release nixpkgs builds Tailscale with.
pkgs.buildGo127Module {
  pname = "tailnet-relay";
  version = "0.1.0";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./go.mod
      ./go.sum
      (lib.fileset.fileFilter (file: file.hasExt "go") ./.)
    ];
  };

  vendorHash = "sha256-nFLgVMVHlqzKDVOvvsR0tuwHEvwFcXMQWCAKz+Jk8j8=";

  meta = {
    description = "Userspace tailnet node that relays its own user's loopback connections to tailnet services";
    mainProgram = "tailnet-relay";
    # The peer check reads socket owners from Linux's sock_diag.
    platforms = lib.platforms.linux;
  };
}
