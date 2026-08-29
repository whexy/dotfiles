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
  #   fusion  - after picking one of `candidates`, further fzf prompts
  #             assign per-role models, restricted to candidates sharing
  #             the picked label's "provider/" prefix (so endpoint and
  #             key stay consistent):
  #               roles      - [{ name, prompt, export }]
  #               candidates - entries with label/env/secrets
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

  mkFusionArm =
    entry:
    let
      roles = entry.fusion.roles;
      candidates = entry.fusion.candidates;
      total = toString (lib.length roles + 1);
      # The picked candidate's env brings endpoint, key, and the main
      # ANTHROPIC_MODEL; fusion only overrides the role defaults after.
      mkCase = c: ''
        ${lib.escapeShellArg c.label})
          ${lib.concatStringsSep "\n      " (
            lib.mapAttrsToList exportStatic (c.env or { }) ++ lib.mapAttrsToList exportSecret (c.secrets or { })
          )}
          ;;
      '';
      mkRole = i: role: ''
        ${role.name}=$(printf '%s\n' "''${candidates[@]}" |
          grep -F "''${main%%/*}/" |
          ${pkgs.fzf}/bin/fzf --prompt='[${toString (i + 1)}/${total}] ${role.prompt}> ' --reverse) || exit 0
        export ${role.export}="''${${role.name}#*/}"
      '';
    in
    ''
      ${lib.escapeShellArg entry.label})
        candidates=(${lib.concatStringsSep " " (map lib.escapeShellArg (map (c: c.label) candidates))})
        main=$(printf '%s\n' "''${candidates[@]}" |
          ${pkgs.fzf}/bin/fzf --prompt='[1/${total}] main model> ' --reverse) || exit 0
        case "$main" in
        ${lib.concatMapStrings mkCase candidates}esac
        export CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT=1
        export CLAUDE_CODE_SUBAGENT_MODEL="''${main#*/}"
        ${lib.concatImapStrings mkRole roles}
        extra_args=()
        ;;
    '';

  mkEntryArm = entry: if entry ? fusion then mkFusionArm entry else mkArm entry;

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
    ${lib.concatMapStrings mkEntryArm entries}
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
