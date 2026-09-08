# totmux / tozellij / toherdr: move an already-running job into a multiplexer.
#
# One script drives all three backends; the Nix prelude below pins the backend
# and the reptyr path. A wrapper is only installed when its backend is enabled,
# and only on Linux, since reptyr is Linux/FreeBSD-only.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.terminal;

  adopt =
    backend:
    pkgs.writeShellApplication {
      name = "to${backend}";
      runtimeInputs =
        with pkgs;
        [
          coreutils
          gnugrep
          gnused
          gawk
          procps
        ]
        ++ lib.optionals (backend == "herdr") [ jq ];
      # The script reads the backend and reptyr path from this prelude instead
      # of argv[0], so a renamed or symlinked wrapper still targets one backend.
      text = ''
        backend=${backend}
        reptyr=${lib.getExe pkgs.reptyr}

      ''
      + builtins.readFile ./adopt.sh;
    };

  wrappers =
    lib.optional cfg.tmux.enable (adopt "tmux")
    ++ lib.optional cfg.zellij.enable (adopt "zellij")
    ++ lib.optional cfg.herdr.enable (adopt "herdr");
in
{
  config = lib.mkIf (cfg.adopt.enable && pkgs.stdenv.isLinux) {
    home.packages = wrappers;
  };
}
