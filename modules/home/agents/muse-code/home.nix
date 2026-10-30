{
  lib,
  perSystem,
  proxy,
  withModelPicker,
  mcp,
  prelude,
}:
let
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
      "MUSE_CUSTOM_HEADERS"
      "MUSE_MODEL"
    ];
    entries = import ./models.nix { inherit proxy; };
  };
in
{
  packages = [ agent ];

  homeFiles.".config/muse/AGENTS.md".text = builtins.readFile ../AGENTS.md;

  # Every host starts on the gateway: the first sync saves the default entry
  # and its credentials, so no host signs in to Meta.
  activation.museSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${agent}/bin/muse-settings-sync
  '';
}
