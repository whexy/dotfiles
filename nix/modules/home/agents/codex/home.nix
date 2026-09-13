{
  pkgs,
  config,
  lib,
  apiAccounts,
  proxyAccounts,
  proxy,
  withModelPicker,
  mcp,
}:
let
  # codex has no MCP config file we can own: servers live in
  # ~/.codex/config.toml, which `codex mcp add`, plugin installs, and login
  # all rewrite. `-c` overrides supply them per launch instead.
  #
  # One `-c` per server, as a single inline TOML table: codex splits a dotted
  # override path on every `.` without honouring TOML quoting, so a dotted
  # path would break on any server or argument containing a dot.
  #
  # The value is parsed as TOML, where JSON's `"key":` is a syntax error, so
  # the table is emitted rather than passed through builtins.toJSON. Strings
  # are JSON-quoted because TOML basic strings share JSON's escape rules.
  toToml =
    value:
    if builtins.isList value then
      "[${lib.concatMapStringsSep "," toToml value}]"
    else if builtins.isAttrs value then
      "{${
        lib.concatStringsSep "," (lib.mapAttrsToList (k: v: "${builtins.toJSON k}=${toToml v}") value)
      }}"
    else
      builtins.toJSON value;

  mcpArgs = lib.concatMap (name: [
    "-c"
    "mcp_servers.${name}=${toToml mcp.servers.${name}}"
  ]) (lib.attrNames mcp.servers);
in
{
  packages = [
    (withModelPicker {
      name = "codex";
      package = pkgs.llm-agents.codex;
      extraArgs = mcpArgs;
      entries = import ./models.nix {
        inherit
          config
          lib
          apiAccounts
          proxyAccounts
          proxy
          ;
      };
    })
  ];
}
