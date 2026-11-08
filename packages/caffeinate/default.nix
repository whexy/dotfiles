# macOS's caffeinate for Linux, on logind inhibitors and, with -d, a Wayland
# idle inhibitor. Tools are referenced by absolute store path so the script
# does not reorder PATH for the utility it runs.
{ pkgs }:
let
  inherit (pkgs) lib;
in
pkgs.writeShellApplication {
  name = "caffeinate";
  text =
    lib.replaceStrings
      [ "@tail@" "@sleep@" "@systemdInhibit@" "@wlinhibit@" ]
      [
        "${pkgs.coreutils}/bin/tail"
        "${pkgs.coreutils}/bin/sleep"
        "${pkgs.systemd}/bin/systemd-inhibit"
        "${pkgs.wlinhibit}/bin/wlinhibit"
      ]
      (builtins.readFile ./caffeinate.sh);
  meta = {
    description = "Keep a Linux machine awake while a command runs, like macOS's caffeinate";
    platforms = lib.platforms.linux;
  };
}
