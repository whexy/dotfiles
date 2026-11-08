{
  pkgs,
  perSystem,
  flake,
  ...
}:
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
  # A resolver that fails, so the server must start with no policy.
  policy = {
    command = "${pkgs.coreutils}/bin/false";
    none = "/no-policy.json";
  };
  moduleFor =
    isDarwin: enabled: tailnetEnabled:
    import ./services.nix { inherit pkgs flake; } isDarwin {
      inherit policy;
      cfg.server = {
        enable = enabled;
        tailnet.enable = tailnetEnabled;
      };
      t3 = "${t3}/bin/t3";
      profileDirectory = profile;
      homeDirectory = "/tmp";
      stateHome = "/tmp/.local/state";
    };
  linux = moduleFor false true true;
  darwin = moduleFor true true true;
  server = linux.systemd.user.services.t3code.Service.ExecStart;
  route = linux.systemd.user.services.t3code-tailnet.Service.ExecStart;
in
assert darwin.launchd.agents.t3code.config.ProgramArguments == [ server ];
assert darwin.launchd.agents.t3code-tailnet.config.ProgramArguments == [ route ];
assert !(moduleFor false true false).systemd.user.services ? t3code-tailnet;
assert !(moduleFor true false true).launchd.agents ? t3code-tailnet;
pkgs.runCommand "t3-tailnet"
  {
    __darwinAllowLocalNetworking = true;
    nativeBuildInputs = [
      python
      pkgs.openssl
    ];
  }
  ''
    export T3_PORT=${toString flake.lib.t3.port} T3_TAILNET_PORT=${toString flake.lib.t3.tailnetPort}
    python ${fixture} test ${server} ${route}
    ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      python ${fixture} actual ${pkgs.lib.getExe perSystem.self.t3code-fork} ${profile}/bin
    ''}
    touch "$out"
  ''
