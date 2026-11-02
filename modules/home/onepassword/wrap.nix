# Wraps a tool started on demand so each run loads its secrets from 1Password
# into that process alone. A tool that ticks often, or that takes its secret
# another way (a header on stdin, a credential command), runs `op-sa read`
# itself.
#
# A value only ever moves by command substitution and the `export` builtin,
# so it reaches no argv, file, or store path, and the program gets it through
# `exec`.
{
  lib,
  pkgs,
  opSa,
  items,
}:
{
  package,
  programs ? [ package.meta.mainProgram ],
  # { VAR = "<items.nix name>"; }
  env,
  # Plain values that describe the loaded secrets, such as the ID of a key,
  # exported only with them and over any value the caller set.
  withSecret ? { },
  # Variables that mean the caller brings their own credentials: when any is
  # set, nothing is loaded. Saving the request matters, since every home
  # shares 1Password's 1,000 a day.
  callerWins ? lib.attrNames env,
  # Also skip when ./.env assigns one of `callerWins`, for a tool that reads
  # that file itself and would lose to an exported value.
  dotenv ? false,
  # Runs that need no credential, such as shell completion, which some tools
  # answer by running themselves on every Tab. `firstArg` and `anyArg` are
  # literal arguments; `env` gives such a run placeholders, unless set, for a
  # tool that refuses to start without them.
  skipWhen ? { },
  # makeWrapper flags for settings that do not depend on the secret.
  wrapperArgs ? [ ],
}:
let
  vars = lib.attrNames env;
  firstArg = skipWhen.firstArg or [ ];
  anyArg = skipWhen.anyArg or [ ];
  skipEnv = skipWhen.env or { };
  skips = firstArg != [ ] || anyArg != [ ];

  isVar = name: builtins.match "[A-Za-z_][A-Za-z0-9_]*" name != null;
  errors =
    map (name: "${name} is not a variable name") (
      lib.filter (name: !isVar name) (
        vars ++ lib.attrNames withSecret ++ callerWins ++ lib.attrNames skipEnv
      )
    )
    ++ map (item: "${item} is not a name in items.nix") (
      lib.filter (item: !items ? ${item}) (lib.attrValues env)
    )
    ++ lib.optional (vars == [ ]) "env names no secret"
    ++ lib.optional (dotenv && callerWins == [ ]) "dotenv needs a variable in callerWins"
    ++ map (key: "skipWhen.${key} is not an option") (
      lib.subtractLists [ "firstArg" "anyArg" "env" ] (lib.attrNames skipWhen)
    )
    ++ lib.optional (skipEnv != { } && !skips) "skipWhen.env needs firstArg or anyArg";

  read = lib.getExe opSa;
  grep = lib.getExe pkgs.gnugrep;
  cases = lib.concatMapStringsSep "|" lib.escapeShellArg;
  warning =
    program:
    "${program}: could not load ${lib.concatStringsSep ", " vars} from 1Password; running without "
    + (if lib.length vars == 1 then "it" else "them");

  # Shell variables the fragment uses are prefixed and unset again: an
  # assignment to a name the caller exported would reach the program.
  fragment = program: ''
    { set +x; } 2>/dev/null
    __op_wrap_load=1
    ${lib.optionalString skips ''
      __op_wrap_skip=
      ${lib.optionalString (firstArg != [ ]) ''
        case "''${1-}" in ${cases firstArg}) __op_wrap_skip=1 ;; esac
      ''}
      ${lib.optionalString (anyArg != [ ]) ''
        for __op_wrap_arg in "$@"; do
          case "$__op_wrap_arg" in ${cases anyArg}) __op_wrap_skip=1 ;; esac
        done
        unset __op_wrap_arg
      ''}
      if [ -n "$__op_wrap_skip" ]; then
        __op_wrap_load=
        ${lib.concatStrings (
          lib.mapAttrsToList (var: value: ''
            export ${var}=''${${var}:-${lib.escapeShellArg value}}
          '') skipEnv
        )}
      fi
      unset __op_wrap_skip
    ''}
    ${lib.concatMapStrings (var: ''
      if [ -n "''${${var}:-}" ]; then __op_wrap_load=; fi
    '') callerWins}
    ${lib.optionalString dotenv ''
      if ${grep} -Eqs '^[[:space:]]*(export[[:space:]]+)?(${lib.concatStringsSep "|" callerWins})[[:space:]]*=' .env; then
        __op_wrap_load=
      fi
    ''}
    if [ -n "$__op_wrap_load" ]; then
      if ${
        lib.concatMapStringsSep " &&\n  " (
          var: ''${var}=$(${read} read ${lib.escapeShellArg env.${var}}) && [ -n "''$${var}" ]''
        ) vars
      }; then
        export ${lib.concatStringsSep " " vars}
        ${lib.concatStrings (
          lib.mapAttrsToList (var: value: ''
            export ${var}=${lib.escapeShellArg value}
          '') withSecret
        )}
      else
        unset ${lib.concatStringsSep " " vars}
        echo ${lib.escapeShellArg (warning program)} >&2
      fi
    fi
    unset __op_wrap_load
  '';

  wrapped = pkgs.symlinkJoin {
    inherit (package) name meta;
    paths = [ package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = lib.concatMapStrings (program: ''
      wrapProgram $out/bin/${lib.escapeShellArg program} \
        ${lib.escapeShellArgs wrapperArgs} \
        --run ${lib.escapeShellArg (fragment program)}
    '') programs;
  };
in
if errors == [ ] then
  wrapped
else
  throw "dotfiles.onepassword.wrap (${package.name}): ${lib.concatStringsSep "; " errors}"
