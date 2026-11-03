{
  pkgs,
  inputs,
  system,
}:

# whexy/t3code's T3 server, which every host runs. It is the fork's derivation
# unchanged, so hosts substitute the path the fork's CI pushed to Cachix
# (whexy-t3code); the attributes added here leave what it builds alone.
let
  inherit (pkgs) lib;
  inherit (inputs.t3code-fork) packages;
  platforms = lib.filter (s: packages.${s} ? t3-server) (lib.attrNames packages);
  fork = packages.${system}.t3-server;
  passthru = {
    # Woodpecker's pin-t3code-fork step moves the t3code-fork input to each
    # commit the fork's CI built and cached.
    updater = null;
  }
  // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
    browser = import ./browser.nix {
      inherit pkgs;
      source = inputs.t3code-fork;
    };
  };
in
# Blueprint reads only meta.platforms to leave the package out elsewhere.
if !lib.elem system platforms then
  {
    meta = { inherit platforms; };
    outPath = throw "t3code-fork: whexy/t3code builds no t3-server for ${system}";
  }
else
  fork
  // passthru
  // {
    passthru = fork.passthru or { } // passthru;
    meta = fork.meta // {
      changelog = "https://github.com/whexy/t3code/commits/${inputs.t3code-fork.rev}";
      inherit platforms;
    };
  }
