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
in
{
  config = lib.mkIf cfg.enable {
    dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };
    home.packages = [
      (config.dotfiles.onepassword.wrap {
        package = asc;
        env.ASC_PRIVATE_KEY = "app-store-connect-api-key";
        withSecret = {
          ASC_KEY_ID = keyId;
          ASC_ISSUER_ID = issuerId;
        };
        # Credentials the caller brings in any form asc takes. A selected
        # profile outranks environment credentials, so loading would waste a
        # request.
        callerWins = [
          "ASC_PRIVATE_KEY"
          "ASC_PRIVATE_KEY_B64"
          "ASC_PRIVATE_KEY_PATH"
          "ASC_KEY_ID"
          "ASC_ISSUER_ID"
          "ASC_PROFILE"
        ];
      })
    ];
  };
}
