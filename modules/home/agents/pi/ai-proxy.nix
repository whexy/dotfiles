# Stamp the gateway endpoints and agenix secret paths into the extension.
#
# The paths are only known to Home Manager, and the extension must not
# guess them. Assigning through `globalThis` satisfies the `declare const`
# in ai-proxy.ts, which keeps that file a plain TypeScript file that still
# type-checks on its own instead of a template with substitution holes.
{
  pkgs,
  proxy,
  defaults,
}:
let
  inherit (pkgs) lib;
  config = {
    inherit (proxy) cfAccessIdPath cfAccessSecretPath;
    gateways = lib.mapAttrsToList (id: gateway: {
      inherit id;
      inherit (gateway)
        name
        baseUrl
        apiKeyPath
        catalogUrl
        qualifiedIds
        ;
      # pi's default model and web-search's summary model, on the gateway
      # serving each.
      fallbackModels = lib.unique (
        lib.optional (defaults.defaultProvider == id) defaults.defaultModel
        ++ lib.optional (defaults.defaultCheapProvider == id) defaults.defaultCheapModel
      );
    }) proxy.gateways;
    # /bin/cat does not exist on NixOS, so the reader cannot rely on an
    # inherited PATH.
    cat = "${pkgs.coreutils}/bin/cat";
  };
in
pkgs.runCommand "pi-ai-proxy.ts"
  {
    declaration = ''
      globalThis.__AI_PROXY_CONFIG__ = ${builtins.toJSON config};
    '';
    passAsFile = [ "declaration" ];
  }
  ''
    cat "$declarationPath" ${./ai-proxy.ts} > $out
  ''
