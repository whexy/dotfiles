# niri event-stream listeners for the Linux bar pills (Eww and Waybar).
#
# A listener folds `niri msg --json event-stream` through ./niri.jq and
# prints a projection of niri's state whenever it changes, so the pills
# follow niri without polling `niri msg`.
{
  lib,
  pkgs,
  niri,
}:
let
  jq = lib.getExe pkgs.jq;
  sleep = lib.getExe' pkgs.coreutils "sleep";

  # `flag` selects jq's output: -c for JSON values, -r for plain text.
  listen =
    name: flag: projection:
    let
      program = pkgs.writeText "${name}.jq" ''
        ${builtins.readFile ./niri.jq}
        changes(${projection})
      '';
    in
    pkgs.writeShellScript name ''
      # The stream ends when niri restarts. Every connection opens with full
      # snapshots, so reconnecting resumes from the current state.
      while :; do
        ${niri} msg --json event-stream 2>/dev/null | ${jq} -n --unbuffered ${flag} -f ${program}
        ${sleep} 1
      done
    '';
in
{
  inherit listen;

  # niri reports focus moves but not ssh sessions that start or end in the
  # focused window, so the read timeout re-checks every 5 seconds.
  sshContext =
    sshWindow:
    pkgs.writeShellScript "niri-ssh-context" ''
      ${listen "niri-focused-window" "-c" "focused_window | .id"} |
        while read -r -t 5 _ || [ $? -gt 128 ]; do
          # Focus can move several times in a row; look up the settled window.
          while read -r -t 0.05 _; do :; done
          ${sshWindow} current </dev/null 2>/dev/null || echo
        done
    '';
}
