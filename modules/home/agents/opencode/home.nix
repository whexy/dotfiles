{
  pkgs,
  config,
  lib,
  apiAccounts,
  proxyAccounts,
  proxy,
  defaults,
  mcp,
  models,
}:
let
  upstream = pkgs.llm-agents.opencode;
  secretPath = name: config.age.secrets.${name}.path;
  secrets = {
    OPENROUTER_API_KEY = secretPath "openrouter-api-key";
  }
  // lib.optionalAttrs apiAccounts {
    OPENAI_API_KEY = secretPath "openai-api-key";
    ANTHROPIC_API_KEY = secretPath "anthropic-api-key";
  }
  // lib.optionalAttrs proxyAccounts (
    proxy.cfAccessSecrets
    // {
      AI_PROXY_API_KEY = proxy.apiKeyPath;
    }
  );
  # Double quotes, not escapeShellArg: the agenix path is a shell fragment
  # that has to expand.
  exportSecret = name: path: ''
    if [ ! -r "${path}" ]; then
      echo "opencode: missing secret: ${path}" >&2
      exit 1
    fi
    export ${name}="$(< "${path}")"
  '';
  launcher = pkgs.writeShellScript "opencode" ''
    set -euo pipefail
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList exportSecret secrets)}
    exec ${lib.getExe upstream} "$@"
  '';
  package = pkgs.runCommand "opencode-with-credentials" { meta.mainProgram = "opencode"; } ''
    mkdir -p $out/bin
    for p in ${upstream}/*; do
      if [ "$(basename "$p")" != bin ]; then
        ln -s "$p" $out/
      fi
    done
    for p in ${upstream}/bin/*; do
      if [ "$(basename "$p")" != opencode ]; then
        ln -s "$p" $out/bin/
      fi
    done
    ln -s ${launcher} $out/bin/opencode
  '';
  settings = import ./config.nix {
    inherit
      lib
      apiAccounts
      proxyAccounts
      proxy
      defaults
      mcp
      models
      ;
  };
in
{
  packages = [ package ];
  shellAliases.oc = "opencode";
  homeFiles = {
    ".config/opencode/opencode.json".text = builtins.toJSON settings;
    ".config/opencode/tui.json".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/tui.json";
      theme = "system";
    };
    # Plugins in this directory are auto-loaded.
    ".config/opencode/plugins/notify.js".source = ./plugins/notify.js;
  }
  // lib.optionalAttrs proxyAccounts {
    ".config/opencode/plugins/ai-proxy.js".source = ./plugins/ai-proxy.js;
  };
}
