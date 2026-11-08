# The Cloudflare Access service token this repo's clients send to the
# services behind Access: the model gateways, the cluster's SearXNG, the NAS
# and the zepbound site. Each sends it as the `CF-Access-Client-Id` and
# `CF-Access-Client-Secret` headers, read from the files at run time.
{ config, lib, ... }:
let
  cfg = config.dotfiles.cloudflareAccess.serviceToken;
in
{
  options.dotfiles.cloudflareAccess.serviceToken = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this home decrypts the service token. Each consumer sets it
        in its own gate, so only homes that send the token hold it.
      '';
    };
    # agenix paths are shell fragments ("''${XDG_RUNTIME_DIR}/agenix/..." on
    # Linux, "$(getconf DARWIN_USER_TEMP_DIR)/agenix/..." on Darwin), so a
    # consumer expands them at run time.
    idPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = config.age.secrets.cf-access-dotfiles-id.path;
      defaultText = lib.literalMD "the agenix path of `cf-access-dotfiles-id`";
      description = "agenix path of the service token's client ID, while `enable` is set.";
    };
    secretPath = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = config.age.secrets.cf-access-dotfiles-secret.path;
      defaultText = lib.literalMD "the agenix path of `cf-access-dotfiles-secret`";
      description = "agenix path of the service token's client secret, while `enable` is set.";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = {
      cf-access-dotfiles-id.file = ../../../secrets/cf-access-dotfiles-id.age;
      cf-access-dotfiles-secret.file = ../../../secrets/cf-access-dotfiles-secret.age;
    };
  };
}
