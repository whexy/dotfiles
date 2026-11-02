{ pkgs, perSystem, ... }:
let
  python = pkgs.python3.withPackages (p: [ p.websockets ]);
  fixture = ./test.py;
  profile = pkgs.runCommand "t3-test-profile" { } ''
    mkdir -p "$out/bin" "$out/etc/profile.d"
    echo 'export T3_TEST_SESSION=loaded' > "$out/etc/profile.d/hm-session-vars.sh"
    cat > "$out/bin/tailscale" <<'SCRIPT'
    #!${pkgs.runtimeShell}
    exec ${python}/bin/python ${fixture} tailscale "$@"
    SCRIPT
    chmod +x "$out/bin/tailscale"
  '';
  t3 = pkgs.writeShellScriptBin "t3" ''
    exec ${python}/bin/python ${fixture} server "$@"
  '';
  moduleFor =
    isDarwin: enabled: tailnetEnabled:
    withPolicy isDarwin enabled tailnetEnabled null;
  withPolicy =
    isDarwin: enabled: tailnetEnabled: policy:
    import ../../modules/home/t3code/services.nix {
      inherit policy;
      pkgs = pkgs // {
        stdenv = pkgs.stdenv // {
          hostPlatform = pkgs.stdenv.hostPlatform // {
            inherit isDarwin;
          };
        };
      };
      inherit (pkgs) lib;
      cfg.server = {
        enable = enabled;
        tailnet.enable = tailnetEnabled;
      };
      t3 = "${t3}/bin/t3";
      profileDirectory = profile;
      homeDirectory = "/tmp";
      gitConfig = "/dev/null";
    };
  linux = moduleFor false true true;
  darwin = moduleFor true true true;
  server = linux.systemdUserServices.t3code.Service.ExecStart;
  route = linux.systemdUserServices.t3code-tailnet.Service.ExecStart;
in
assert darwin.launchdAgents.t3code.config.ProgramArguments == [ server ];
assert darwin.launchdAgents.t3code-tailnet.config.ProgramArguments == [ route ];
assert !(moduleFor false true false).systemdUserServices ? t3code-tailnet;
assert !(moduleFor true false true).launchdAgents ? t3code-tailnet;
assert !linux.systemdUserServices.t3code.Service ? Environment;
assert
  (withPolicy false true true "/policy.json").systemdUserServices.t3code.Service.Environment == [
    "T3CODE_DEV_MANAGED_POLICY_PATH=/policy.json"
  ];
assert
  (withPolicy true true true "/policy.json").launchdAgents.t3code.config.EnvironmentVariables == {
    T3CODE_DEV_MANAGED_POLICY_PATH = "/policy.json";
  };
pkgs.runCommand "t3-tailnet"
  {
    __darwinAllowLocalNetworking = true;
    nativeBuildInputs = [
      python
      pkgs.openssl
    ];
  }
  ''
    python ${fixture} test ${server} ${route}
    ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      python ${fixture} actual ${pkgs.lib.getExe perSystem.self.t3code-nightly} ${profile}/bin
    ''}
    touch "$out"
  ''
