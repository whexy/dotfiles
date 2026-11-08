# Runs `t3code-policy` against a fixture policy server, with a stand-in T3
# that accepts policies containing `"valid": true` and a server service that
# is a file.
{ pkgs, flake, ... }:
let
  inherit (pkgs) lib;
  t3 = pkgs.writeShellScript "t3" ''
    case "$*" in
    --version) echo test ;;
    "policy check "*)
      echo "$3" >>"$T3_TEST_ROOT/checks"
      ${lib.getExe pkgs.gnugrep} -q '"valid": true' "$3" && exit 0
      echo "[00:00:00] ERROR (#1): policy is invalid"
      exit 1
      ;;
    "policy show") cat "$T3CODE_DEV_MANAGED_POLICY_PATH" ;;
    esac
  '';
  command = import ../../modules/home/t3code/policy-command.nix {
    inherit pkgs lib;
    t3 = "${t3}";
    # The test points T3CODE_POLICY_URL and T3CODE_POLICY_ALERT_URL at its
    # fixture server.
    url = "http://127.0.0.1:9/unused.json";
    alertUrl = "http://127.0.0.1:9/unused";
    editorUrl = "https://editor.invalid/";
    none = "/no-policy.json";
    server = {
      running = ''[ -e "$T3_TEST_ROOT/running" ]'';
      restart = ''echo restart >>"$T3_TEST_ROOT/restarts"'';
    };
  };
  # The updater's units read status.json where the wrapper writes it.
  units =
    isDarwin:
    import ../t3-tailnet/services.nix { inherit pkgs flake; } isDarwin {
      cfg.server = {
        enable = true;
        tailnet.enable = false;
      };
      t3 = "${t3}";
      policy = {
        command = lib.getExe command;
        none = "/no-policy.json";
      };
      profileDirectory = "/profile";
      homeDirectory = "/home";
      stateHome = "/state";
    };
in
assert
  (units false).systemd.user.services.t3code-policy-update.Service.Environment == [
    "XDG_STATE_HOME=/state"
  ];
assert
  (units true).launchd.agents.t3code-policy-update.config.EnvironmentVariables == {
    XDG_STATE_HOME = "/state";
  };
pkgs.runCommand "t3-policy"
  {
    __darwinAllowLocalNetworking = true;
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    python ${./test.py} ${lib.getExe command}
    touch "$out"
  ''
