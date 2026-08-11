# Linux tracing, profiling, and fuzzing tools.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = lib.mkIf (config.dotfiles.tooling.debug.enable && pkgs.stdenv.isLinux) {
    home.packages =
      with pkgs;
      [
        bpftrace
        ltrace
        perf
        rr
        strace
      ]
      ++ lib.optionals pkgs.stdenv.isx86_64 [
        # only available on x86_64 Linux
        aflplusplus
        valgrind
      ];
  };
}
