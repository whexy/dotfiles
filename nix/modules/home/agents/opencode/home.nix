{
  pkgs,
  config,
  lib,
  apiAccounts,
  proxyAccounts,
}:
let
  upstream = pkgs.llm-agents.opencode2;
  secretExports = {
    OPENCODE_API_KEY = config.age.secrets.opencode-api-key.path;
  }
  // lib.optionalAttrs apiAccounts {
    OPENAI_API_KEY = config.age.secrets.openai-api-key.path;
    ANTHROPIC_API_KEY = config.age.secrets.anthropic-api-key.path;
    DEEPSEEK_API_KEY = config.age.secrets.deepseek-api-key.path;
    OPENROUTER_API_KEY = config.age.secrets.openrouter-api-key.path;
  }
  // lib.optionalAttrs proxyAccounts {
    AI_PROXY_API_KEY = config.age.secrets.ai-proxy-api-key.path;
  };
  exportSecret = name: path: ''
    if [ ! -r ${lib.escapeShellArg path} ]; then
      echo "opencode2: missing secret: ${path}" >&2
      exit 1
    fi
    export ${name}="$(< ${lib.escapeShellArg path})"
  '';
  launcher = pkgs.writeShellScriptBin "opencode2" ''
    set -euo pipefail
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList exportSecret secretExports)}
    exec ${lib.escapeShellArg (upstream + "/bin/opencode2")} "$@"
  '';
  package = pkgs.runCommand "opencode2-with-credentials" { meta.mainProgram = "opencode2"; } ''
    mkdir -p $out
    for path in ${upstream}/*; do
      ln -s "$path" $out/
    done
    rm $out/bin
    mkdir $out/bin
    for binary in ${upstream}/bin/*; do
      ln -s "$binary" $out/bin/
    done
    rm $out/bin/opencode2
    ln -s ${launcher}/bin/opencode2 $out/bin/opencode2
  '';
  settings = import ./config.nix {
    inherit
      config
      lib
      apiAccounts
      proxyAccounts
      ;
  };
in
{
  inherit settings;
  tui = import ./tui.nix;
  inherit package;
  shellAliases.oc = "opencode2";
  homeFiles = import ./files.nix {
    inherit
      config
      lib
      proxyAccounts
      ;
    baseURL = settings.provider.ai-proxy.options.baseURL or null;
  };
}
