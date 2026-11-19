# Google's Antigravity CLI, `agy`, on CLIProxyAPI's Antigravity accounts.
#
# agy reaches a gateway in Gemini API-key mode: `modelProvider = "gemini"` in
# its settings, the key in GEMINI_API_KEY and the origin in
# GOOGLE_GEMINI_BASE_URL. It then lists only its own Gemini models and asks
# for them without the effort suffix (`gemini-4-argon`), which CLIProxyAPI
# serves as aliases of its Antigravity models. That mode sends no headers of
# our own, so it cannot pass Cloudflare Access: agy takes the gateway's
# tailnet origin, or the relay where the home has one.
{
  config,
  lib,
  pkgs,
  ...
}@args:
let
  cfg = config.dotfiles.agents;
  gateways = config.dotfiles.llmGateways;
  cliproxyapi = gateways.gateways.cliproxyapi;
  route = gateways.routes.cliproxyapi;
  baseUrl = if gateways.relay.enable then route.baseUrl else cliproxyapi.tailnetUrl;

  # agy rewrites its settings file, so activation sets the one key it needs
  # and keeps the rest.
  settingsFile = "${config.home.homeDirectory}/.gemini/antigravity-cli/settings.json";
  geminiProvider = pkgs.writeShellScript "agy-gemini-provider" ''
    set -eo pipefail
    jq=${lib.getExe pkgs.jq}
    document=${lib.escapeShellArg settingsFile}
    if "$jq" -e '.modelProvider == "gemini"' "$document" >/dev/null 2>&1; then
      exit 0
    fi
    if [ ! -e "$document" ]; then
      after=$("$jq" -n '{modelProvider: "gemini"}')
    elif ! after=$("$jq" '.modelProvider = "gemini"' "$document"); then
      echo "agy: could not update $document; leaving it unchanged" >&2
      exit 0
    fi
    mkdir -p "$(dirname "$document")"
    temporary=$(mktemp "$document.XXXXXX")
    printf '%s\n' "$after" >"$temporary"
    chmod 600 "$temporary"
    mv "$temporary" "$document"
  '';
in
{
  options.dotfiles.agents.antigravity.enable = lib.mkOption {
    type = lib.types.bool;
    default = (args.osConfig.dotfiles.network.tailscale.enable or false) || gateways.relay.enable;
    defaultText = lib.literalExpression "osConfig.dotfiles.network.tailscale.enable or false || config.dotfiles.llmGateways.relay.enable";
    description = ''
      Whether to install the Antigravity CLI (`agy`). It needs CLIProxyAPI's
      tailnet origin or the tailnet relay, so a standalone home on the
      tailnet sets it itself.
    '';
  };

  config = lib.mkIf (cfg.enable && cfg.antigravity.enable) {
    dotfiles.agents.harnesses.agy = {
      package = pkgs.llm-agents.antigravity-cli;
      prelude =
        lib.optionalString gateways.relay.enable ''
          ${route.relayCheck.listenerCheck} ${lib.escapeShellArgs route.relayCheck.listeners} || exit 1
        ''
        + ''
          GEMINI_API_KEY=$(cat "${cliproxyapi.apiKeyPath}") || exit 1
          export GEMINI_API_KEY
          export GOOGLE_GEMINI_BASE_URL=${lib.escapeShellArg baseUrl}
        '';
      rules.file = ".gemini/GEMINI.md";
      skillsRoot = ".gemini/config/skills";
    };

    home = {
      file.".gemini/config/mcp_config.json".text = builtins.toJSON {
        mcpServers = cfg.mcp.rendered.agy;
      };
      activation.agySettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${geminiProvider}
      '';
    };
  };
}
