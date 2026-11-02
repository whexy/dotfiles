# dotfiles.onepassword.wrap against a stub op-sa: which runs load, what the
# program receives, and that no value reaches argv, stderr, or the store.
{ pkgs, ... }:
let
  inherit (pkgs) lib;

  # Prints $STUB/<name>, fails when it is missing, and logs each call.
  stub = pkgs.writeShellApplication {
    name = "op-sa";
    text = ''
      printf '%s\n' "$*" >>"$STUB/calls"
      if [ ! -f "$STUB/$2" ]; then
        echo "op-sa: stub has no $2" >&2
        exit 1
      fi
      cat "$STUB/$2"
    '';
  };

  # Prints the variables it receives and its arguments.
  probe =
    let
      script = ''
        for var in A B C K S; do
          printf '%s=%s\n' "$var" "''${!var-<unset>}"
        done
        printf 'arg=%s\n' "$@"
      '';
    in
    pkgs.symlinkJoin {
      name = "probe";
      paths = [
        (pkgs.writeShellScriptBin "probe" script)
        (pkgs.writeShellScriptBin "probe2" script)
      ];
      meta.mainProgram = "probe";
    };

  wrap = import ../../modules/home/onepassword/wrap.nix {
    inherit lib pkgs;
    opSa = stub;
    items = {
      item-a = "op://vault/a/credential";
      item-b = "op://vault/b/credential";
    };
  };

  both = wrap {
    package = probe;
    programs = [
      "probe"
      "probe2"
    ];
    env = {
      A = "item-a";
      B = "item-b";
    };
    withSecret.C = "plain c";
  };
  one = wrap {
    package = probe;
    env.A = "item-a";
    callerWins = [
      "A"
      "K"
    ];
    dotenv = true;
    skipWhen = {
      firstArg = [ "complete" ];
      anyArg = [ "--generate" ];
      env.B = "place holder";
    };
    wrapperArgs = [
      "--set-default"
      "S"
      "server"
    ];
  };
  overwrite = wrap {
    package = probe;
    env.A = "item-a";
    callerWins = [ ];
  };

  fails = args: !(builtins.tryEval (wrap ({ package = probe; } // args))).success;
in
assert lib.getExe both == "${both}/bin/probe";
assert fails { env.A = "no-such-item"; };
assert fails { env."A-B" = "item-a"; };
assert fails { env = { }; };
assert fails {
  env.A = "item-a";
  skipWhen.first = [ "complete" ];
};
assert fails {
  env.A = "item-a";
  skipWhen.env.B = "place holder";
};
pkgs.runCommand "op-wrap-check" { } ''
  set -euo pipefail
  export STUB=$PWD/stub
  mkdir stub work
  cd work
  printf secret-a >"$STUB/item-a"
  printf 'secret-b\nsecond line' >"$STUB/item-b"

  fail() { echo "FAIL: $*" >&2; exit 1; }
  # run <name> <command>...: stdout to out, stderr to err, calls reset.
  run() {
    rm -f "$STUB/calls"
    touch "$STUB/calls"
    "''${@:2}" >out 2>err || fail "$1: exit $?"
  }
  has() { grep -qxF -- "$2" out || fail "$1: no '$2' in: $(cat out)"; }
  calls() {
    [ "$(cat "$STUB/calls")" = "$2" ] || fail "$1: calls were: $(cat "$STUB/calls")"
  }
  warned() {
    [ "$(grep -c 'could not load' err)" = "$2" ] || fail "$1: stderr was: $(cat err)"
  }

  # A load sets every secret and withSecret, one read per name, in each program.
  for program in probe probe2; do
    run "load $program" ${both}/bin/$program x 'y z'
    has load A=secret-a
    has load B=secret-b
    has load 'second line'
    has load 'C=plain c'
    has load arg=x
    has load 'arg=y z'
    calls load "read item-a
  read item-b"
    warned load 0
  done

  # The caller's value wins and nothing is read; withSecret stays unset.
  run caller env A=mine ${both}/bin/probe
  has caller A=mine
  has caller B='<unset>'
  has caller C='<unset>'
  calls caller ""
  # Any variable callerWins lists counts, even one that is no secret.
  run caller-list env K=key ${one}/bin/probe
  has caller-list A='<unset>'
  calls caller-list ""
  # An empty value is no value.
  run caller-empty env A= ${one}/bin/probe
  has caller-empty A=secret-a
  # Without callerWins, the loaded value overwrites the caller's.
  run overwrite env A=mine ${overwrite}/bin/probe
  has overwrite A=secret-a
  # withSecret overwrites too, since it describes the loaded secret.
  run with-secret env C=mine ${both}/bin/probe
  has with-secret 'C=plain c'

  # dotenv: a callerWins assignment in ./.env skips the load.
  printf '# comment\n  export K = 1\n' >.env
  run dotenv ${one}/bin/probe
  calls dotenv ""
  printf 'OTHER_A=1\n' >.env
  run dotenv-other ${one}/bin/probe
  calls dotenv-other "read item-a"
  printf 'A=1\n' >.env
  run no-dotenv ${both}/bin/probe
  has no-dotenv A=secret-a
  rm .env

  # skipWhen matches its literal arguments only.
  run skip-first ${one}/bin/probe complete x
  calls skip-first ""
  has skip-first A='<unset>'
  run skip-any ${one}/bin/probe x --generate
  calls skip-any ""
  # A skipped run gets skipWhen.env, unless set; a loading run does not.
  has skip-any 'B=place holder'
  run skip-env-caller env B=mine ${one}/bin/probe complete
  has skip-env-caller B=mine
  run skip-later ${one}/bin/probe x complete
  calls skip-later "read item-a"
  has skip-later B='<unset>'
  run skip-glob ${one}/bin/probe 'comp*'
  calls skip-glob "read item-a"

  # wrapperArgs apply on every run.
  run wrapper-args ${one}/bin/probe
  has wrapper-args S=server
  run wrapper-args-caller env S=mine ${one}/bin/probe
  has wrapper-args-caller S=mine

  # A failed load exports none of the secrets, warns once, and runs.
  mv "$STUB/item-b" "$STUB/item-b.off"
  run partial ${both}/bin/probe2
  has partial A='<unset>'
  has partial B='<unset>'
  has partial C='<unset>'
  warned partial 1
  grep -qxF 'probe2: could not load A, B from 1Password; running without them' err ||
    fail "partial: stderr was: $(cat err)"
  # A variable the caller exported empty keeps its export flag, so a value
  # loaded before the failure must be unset to stay out of the program.
  run partial-exported env A= B= ${both}/bin/probe
  has partial-exported A='<unset>'
  # An empty secret counts as a failed load.
  : >"$STUB/item-b"
  run empty ${both}/bin/probe
  has empty A='<unset>'
  warned empty 1
  mv "$STUB/item-b.off" "$STUB/item-b"

  # xtrace from the caller's environment traces no value.
  run xtrace env SHELLOPTS=braceexpand:hashall:interactive-comments:xtrace ${both}/bin/probe
  has xtrace A=secret-a
  if grep -qF secret- err; then fail "xtrace: stderr has a secret"; fi

  # op-sa's argv holds item names only, and no wrapper sets -x.
  run argv ${both}/bin/probe
  calls argv "read item-a
  read item-b"
  for script in ${both}/bin/probe ${both}/bin/probe2 ${one}/bin/probe; do
    if grep -qE 'set -x|secret-' "$script"; then fail "$script traces or holds a value"; fi
  done
  [ -x ${both}/bin/.probe-wrapped ] && [ -x ${both}/bin/.probe2-wrapped ] ||
    fail "not every program is wrapped"

  touch "$out"
''
