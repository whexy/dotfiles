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

  # `named <name>` prints the reference `items.nix` gives the name.
  named = ''
    named() {
      case "$1" in
        ${lib.concatStrings (
          lib.mapAttrsToList (name: reference: ''
            ${name}) echo ${lib.escapeShellArg reference} ;;
          '') (import ./items.nix)
        )}
        *) return 1 ;;
      esac
    }
  '';

  # The service account needs no desktop app. On WSL, pkgs' `op` is Windows'
  # op.exe, which the token never reaches, so it would ask the app to unlock.
  cli = pkgs._1password-cli.linux or pkgs._1password-cli;

  opSa = pkgs.writeShellApplication {
    name = "op-sa";
    runtimeInputs = [
      cli
      pkgs.jq
    ];
    text =
      if hasToken then
        ''
          vaults=(${lib.escapeShellArgs (lib.attrValues (import ./vaults.nix))})
          ${named}
          # `token` stays unexported: each op call gets it in its own environment.
          candidates=(${lib.escapeShellArgs config.age.identityPaths})
          identities=()
          for identity in "''${candidates[@]}"; do
            if [ -r "$identity" ]; then
              identities+=(-i "$identity")
            fi
          done
          if ! token=$(${lib.getExe config.age.package} --decrypt "''${identities[@]}" ${tokenFile}); then
            echo "op-sa: could not decrypt this home's 1Password service-account token" >&2
            exit 1
          fi
        ''
        + builtins.readFile ./op-sa.sh
      else
        ''
          echo "op-sa: this home has no 1Password service account (AGENTS.md, \"Secrets\")" >&2
          exit 1
        '';
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
      default = opSa;
      readOnly = true;
      description = ''
        `op-sa`, which tools run as `op-sa read <name>`, with a name from
        `items.nix`, when they need the secret.
      '';
    };
  };

  config = lib.mkMerge [
    {
      home.packages = [ opSa ];
    }

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
