# My App Store Connect API key, where Apple's tools and my scripts find it.
#
# Apple serves a key's .p8 only once, at creation, so the agenix secret is
# its only lasting copy. altool finds the key by ID in
# ~/.appstoreconnect/private_keys; xcodebuild, notarytool, and API scripts
# take it from the ASC_* variables, the names App Store Connect CLIs such as
# `asc` read.
{ config, lib, ... }:
let
  cfg = config.dotfiles.tooling.appStoreConnect;

  # The IDs authenticate nothing without the key, so they stay in plaintext.
  # They name the key in the secret; replace them when re-encrypting it.
  keyId = "8QCF5687D8";
  issuerId = "ef1c3fa8-e9ae-4581-b6c8-fea147b0786a";
  keyPath = "${config.home.homeDirectory}/.appstoreconnect/private_keys/AuthKey_${keyId}.p8";
in
{
  config = lib.mkIf cfg.enable {
    age.secrets.app-store-connect-api-key = {
      file = ../../../secrets/app-store-connect-api-key.age;
      path = keyPath;
    };

    home.sessionVariables = {
      ASC_KEY_ID = keyId;
      ASC_ISSUER_ID = issuerId;
      ASC_PRIVATE_KEY_PATH = keyPath;
    };
  };
}
