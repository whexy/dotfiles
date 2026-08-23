# Wrap an agent CLI with an fzf provider/model picker.
#
# claude and codex cannot switch models while running; the model must be
# fixed before launch (claude: ANTHROPIC_* env vars, codex: -m flag). On
# interactive launches the wrapper prompts with fzf, exports the env for
# the selected provider/model (reading API keys from agenix secrets at
# runtime), and execs the real binary. Launches with arguments or without
# a TTY skip the picker so scripts keep working.
{ pkgs, lib }:
{
  # Binary name; also becomes the picker's prompt.
  name,
  # Upstream package providing bin/<name>.
  package,
  # Selection entries:
  #   label   - shown in fzf, e.g. "anthropic/claude-opus-5"
  #   env     - static env vars (attrset of strings)
  #   secrets - env var -> secret file path, read at runtime
  #   args    - extra CLI args prepended to the invocation
  entries,
}:
let
  exportStatic = var: value: "export ${var}=${lib.escapeShellArg value}";

  exportSecret =
    var: path:
    lib.concatStringsSep "\n" [
      "if [ ! -r ${lib.escapeShellArg path} ]; then"
      "  echo '${name}: missing secret: ${path}' >&2"
      "  exit 1"
      "fi"
      "export ${var}=\"$(cat ${lib.escapeShellArg path})\""
    ];

  mkArm = entry: ''
    ${lib.escapeShellArg entry.label})
      ${lib.concatStringsSep "\n  " (
        lib.mapAttrsToList exportStatic (entry.env or { })
        ++ lib.mapAttrsToList exportSecret (entry.secrets or { })
        ++ [ "extra_args=(${lib.concatStringsSep " " (map lib.escapeShellArg (entry.args or [ ]))})" ]
      )}
      ;;
  '';

  picker = pkgs.writeShellScriptBin name ''
    set -euo pipefail

    real=${lib.escapeShellArg (package + "/bin/${name}")}

    # Arguments or a pipe mean a scripted launch: the caller already
    # chose the model and env.
    if [ "$#" -gt 0 ] || [ ! -t 0 ]; then
      exec "$real" "$@"
    fi

    choice=$(
      printf '%s\n' ${lib.concatStringsSep " " (map (e: lib.escapeShellArg e.label) entries)} |
        ${pkgs.fzf}/bin/fzf --prompt='${name}> ' --reverse --height='~100%' \
          --header='Select provider/model'
    ) || exit 0

    extra_args=()
    case "$choice" in
    ${lib.concatMapStrings mkArm entries}
    esac

    exec "$real" "''${extra_args[@]}" "$@"
  '';
in
# Re-expose the upstream package with bin/<name> shadowed by the picker.
pkgs.runCommand "${name}-picker" { meta.mainProgram = name; } ''
  mkdir -p $out
  for p in ${package}/*; do
    ln -s "$p" $out/
  done
  if [ -L $out/bin ]; then
    rm $out/bin
    mkdir $out/bin
    for f in ${package}/bin/*; do
      ln -s "$f" $out/bin/
    done
  fi
  rm -f $out/bin/${name}
  ln -s ${picker}/bin/${name} $out/bin/${name}
''
