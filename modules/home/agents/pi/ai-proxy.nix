# Stamp the proxy endpoint and agenix secret paths into the extension.
#
# The paths are only known to Home Manager, and the extension must not
# guess them. Assigning through `globalThis` satisfies the `declare const`
# in ai-proxy.ts, which keeps that file a plain TypeScript file that still
# type-checks on its own instead of a template with substitution holes.
{ pkgs, proxy }:
let
  config = {
    inherit (proxy)
      baseUrl
      apiKeyPath
      cfAccessIdPath
      cfAccessSecretPath
      ;
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
