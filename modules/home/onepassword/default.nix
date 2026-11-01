# Credentials that rotate, such as API keys and access tokens, live in
# 1Password. A tool loads its key when it runs, into its own process; nothing
# keeps a copy. Secrets the system needs to boot, evaluate, or activate offline
# stay in agenix, and so does each home's service-account token (AGENTS.md,
# "Secrets").
{
  config,
  lib,
  pkgs,
  ...
}@args:
let
  cfg = config.dotfiles.onepassword;
  osConfig = args.osConfig or null;

  # Each home signs in as its own read-only service account, so revoking that
  # account in 1Password cuts off this home alone.
  tokenName =
    if cfg.serviceAccount == null then
      null
    else
      "onepassword-${lib.replaceStrings [ "@" ] [ "-" ] cfg.serviceAccount}.age";
  tokenFile = ../../../secrets + "/${tokenName}";
  hasToken = tokenName != null && builtins.pathExists tokenFile;

  references = lib.concatStrings (
    lib.mapAttrsToList (name: reference: ''
      ${name}) reference=${lib.escapeShellArg reference} ;;
    '') (import ./items.nix)
  );

  opSecret = pkgs.writeShellApplication {
    name = "op-secret";
    runtimeInputs = [ pkgs._1password-cli ];
    text = ''
      if [ "$#" -ne 1 ]; then
        echo "usage: op-secret <name>" >&2
        exit 2
      fi
      case "$1" in
        ${references}
        *)
          echo "op-secret: no item named $1 in modules/home/onepassword/items.nix" >&2
          exit 2
          ;;
      esac
    ''
    + (
      if hasToken then
        ''
          candidates=(${lib.escapeShellArgs config.age.identityPaths})
          identities=()
          for identity in "''${candidates[@]}"; do
            if [ -r "$identity" ]; then
              identities+=(-i "$identity")
            fi
          done
          # Only op sees the token.
          if ! OP_SERVICE_ACCOUNT_TOKEN=$(${lib.getExe config.age.package} --decrypt "''${identities[@]}" ${tokenFile}); then
            echo "op-secret: could not decrypt this home's 1Password service-account token" >&2
            exit 1
          fi
          export OP_SERVICE_ACCOUNT_TOKEN
          exec op read --no-newline "$reference"
        ''
      else
        ''
          echo "op-secret: this home has no 1Password service account (AGENTS.md, \"Secrets\")" >&2
          exit 1
        ''
    );
  };
in
{
  options.dotfiles.onepassword = {
    serviceAccount = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default =
        if osConfig != null then "${config.home.username}@${osConfig.dotfiles.host.hostName}" else null;
      defaultText = lib.literalExpression ''"''${config.home.username}@''${osConfig.dotfiles.host.hostName}"'';
      example = "whexy@venus";
      description = ''
        This home's 1Password service account, `<user>@<host>`. Its token is
        `secrets/onepassword-<user>-<host>.age`. Standalone homes have no
        host name to derive it from and set it themselves.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = opSecret;
      readOnly = true;
      description = ''
        `op-secret <name>`, which prints the secret `items.nix` names. Tools
        call it when they need the secret.
      '';
    };
  };

  config = lib.mkMerge [
    { home.packages = [ opSecret ]; }

    (lib.mkIf (!hasToken) {
      warnings = [
        ''
          This home has no 1Password service-account token
          (${
            if tokenName == null then
              "dotfiles.onepassword.serviceAccount is unset"
            else
              "secrets/${tokenName} does not exist"
          }), so tools that load their keys from 1Password run without them.
          Add one as AGENTS.md describes under "Secrets".
        ''
      ];
    })
  ];
}
