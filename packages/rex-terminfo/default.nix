# Rex's xterm-rex terminfo entry. Rex publishes it only through its app, so
# the source is vendored from `rex terminfo show`. Rex keeps the entry
# append-only, so a stale copy only lacks newer capabilities; refresh it with
#
#   rex terminfo show > packages/rex-terminfo/xterm-rex.terminfo
{ pkgs }:

pkgs.runCommand "rex-terminfo"
  {
    src = ./xterm-rex.terminfo;
    nativeBuildInputs = [ pkgs.ncurses ];
  }
  ''
    mkdir -p $out/share/terminfo
    tic -x -o $out/share/terminfo $src
  ''
