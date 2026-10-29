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
    import ../../modules/home/agents/t3code/home.nix {
      pkgs = pkgs // {
        stdenv = pkgs.stdenv // {
          hostPlatform = pkgs.stdenv.hostPlatform // {
            inherit isDarwin;
          };
        };
      };
      config = {
        dotfiles.agents.t3code = {
          package = t3;
          server = {
            enable = enabled;
            tailnet.enable = tailnetEnabled;
            tunnel.enable = false;
          };
        };
        home = {
          profileDirectory = profile;
          homeDirectory = "/tmp";
        };
      };
      inherit (pkgs) lib;
      perSystem = { };
      flake = { };
      proxy = { };
      gitConfig = "/dev/null";
      mkTunnel = _: { };
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
    python ${fixture} actual ${pkgs.lib.getExe perSystem.self.t3code-nightly} ${profile}/bin
    touch "$out"
  ''
