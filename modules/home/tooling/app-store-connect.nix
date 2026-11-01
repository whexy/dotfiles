# App Store Connect: the asc CLI, signed in with my API key.
#
# Apple serves a key's .p8 only once, at creation, so the 1Password item is
# its only lasting copy. asc's wrapper loads it on each run into that asc
# process alone. With the key, its ID, and the issuer in the environment, asc
# skips the keychain, so no home needs `asc auth login`.
{
  config,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.tooling.appStoreConnect;
  inherit (perSystem.self) asc;

  # The IDs authenticate nothing without the key, so they stay in plaintext.
  # They name the key in the secret; replace them when replacing the key.
  keyId = "8QCF5687D8";
  issuerId = "ef1c3fa8-e9ae-4581-b6c8-fea147b0786a";

  loadKey = ''
    if ASC_PRIVATE_KEY=$(${lib.getExe config.dotfiles.onepassword.package} read app-store-connect-api-key); then
      export ASC_PRIVATE_KEY ASC_KEY_ID=${keyId} ASC_ISSUER_ID=${issuerId}
    else
      unset ASC_PRIVATE_KEY
      echo "asc: could not load the App Store Connect API key" >&2
    fi
  '';
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.symlinkJoin {
        inherit (asc) name meta;
        paths = [ asc ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/asc --run ${lib.escapeShellArg loadKey}
        '';
      })
    ];
  };
}
