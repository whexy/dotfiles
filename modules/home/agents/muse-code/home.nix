{
  pkgs,
  config,
  lib,
  perSystem,
  proxy,
  defaults,
  withModelPicker,
  mcp,
  prelude,
}:
let
  # The shim is a service, not a session process: Muse fetches its catalog
  # from it on every start, and a launch that finds it down fails.
  shimPort = 27182;
  shimBaseUrl = "http://127.0.0.1:${toString shimPort}/v1";

  # Muse's MCP shape names the transport and expands `${VAR}` in header
  # values, like Claude's; local servers take a command plus its arguments.
  toMuse =
    server:
    if server ? url then
      {
        transport = "streamable_http";
        inherit (server) url;
      }
      // lib.optionalAttrs (server ? headers) { inherit (server) headers; }
    else
      {
        transport = "stdio";
        inherit (server) command;
        args = server.args or [ ];
      }
      // lib.optionalAttrs (server ? env) { inherit (server) env; };

  agent = withModelPicker {
    name = "muse";
    package = perSystem.self.muse-code;
    mcpServers = lib.mapAttrs (_: toMuse) mcp.servers;
    inherit prelude;
    managedLinks = [
      "AGENTS.md"
      "skills"
    ];
    maintainedSettings = {
      schema_version = 1;
    };
    resetEnv = [
      "META_API_KEY"
      "MUSE_MODEL"
    ];
    entries = import ./models.nix {
      inherit
        proxy
        defaults
        shimBaseUrl
        ;
    };
  };

  inherit (pkgs.stdenv.hostPlatform) isDarwin;

  # Agenix secret paths are shell fragments, so the wrapper resolves them
  # before execing the shim, which re-reads the files on every request.
  shimServe = pkgs.writeShellScript "muse-shim-serve" ''
    export MUSE_SHIM_UPSTREAM=${lib.escapeShellArg proxy.baseUrl}
    export MUSE_SHIM_PORT=${toString shimPort}
    export MUSE_SHIM_CF_ID_FILE="${proxy.cfAccessIdPath}"
    export MUSE_SHIM_CF_SECRET_FILE="${proxy.cfAccessSecretPath}"
    exec ${lib.getExe perSystem.self.muse-shim}
  '';
in
{
  packages = [ agent ];

  homeFiles.".config/muse/AGENTS.md".text = builtins.readFile ../AGENTS.md;

  activation.museSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${agent}/bin/muse-settings-sync
  '';

  systemdUserServices = lib.optionalAttrs (!isDarwin) {
    muse-shim = {
      Unit.Description = "Loopback CLIProxyAPI bridge for Muse Code";
      Service = {
        ExecStart = "${shimServe}";
        Restart = "on-failure";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };

  launchdAgents = lib.optionalAttrs isDarwin {
    muse-shim = {
      enable = true;
      config = {
        ProgramArguments = [ "${shimServe}" ];
        RunAtLoad = true;
        KeepAlive.SuccessfulExit = false;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/muse-shim.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/muse-shim.log";
      };
    };
  };
}
