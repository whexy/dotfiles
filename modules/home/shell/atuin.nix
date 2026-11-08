{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.dotfiles.shell;
  inherit (pkgs) atuin;
  relay = config.dotfiles.tailnetRelay;
  server = "https://${flake.lib.tailnetHost "atuin"}";

  # The sync session token goes to whatever listens on the forward's port,
  # so every command that may reach the server checks that this user holds
  # it. The commands each prompt runs only read and write the local store,
  # and skip the check. When it fails, Atuin keeps working locally with a
  # copy of the config whose server address nothing can listen on.
  offlineConfig = pkgs.linkFarm "atuin-offline-config" {
    "config.toml" = (pkgs.formats.toml { }).generate "config.toml" (
      config.programs.atuin.settings
      // {
        auto_sync = false;
        sync_address = "http://127.0.0.1:0";
      }
    );
  };
  viaRelay = pkgs.symlinkJoin {
    name = "atuin-via-tailnet-relay";
    paths = [ atuin ];
    postBuild = ''
      rm $out/bin/atuin
      cat > $out/bin/atuin <<EOF
      #!${pkgs.runtimeShell}
      case "\''${1-} \''${2-}" in
        "history start" | "search "* | "init "*) ;;
        *)
          if ! reason=\$(${relay.checker} ${relay.forwards.atuin.address} 2>&1); then
            [ "\''${1-}" = history ] || echo "\$reason; Atuin sync is off" >&2
            export ATUIN_CONFIG_DIR=${offlineConfig}
          fi
          ;;
      esac
      exec ${lib.getExe atuin} "\$@"
      EOF
      chmod +x $out/bin/atuin
    '';
    meta.mainProgram = "atuin";
  };
  decrypt = flake.lib.agenixDecrypt {
    inherit pkgs;
    inherit (config.age) identityPaths package;
  };
in
{
  config = lib.mkIf (cfg.zsh.devExtras || cfg.nushell.devExtras) {
    programs.atuin = {
      settings.sync_address = if relay.enable then relay.forwards.atuin.url else server;
      package = lib.mkIf relay.enable viaRelay;
    };
    dotfiles.tailnetRelay.forwards.atuin = lib.mkIf relay.enable {
      port = 47303;
      upstream = server;
    };

    # agenix decrypts from a systemd user service or launchd agent that may
    # run after activation, so read the encrypted credentials directly. The
    # store persists, so this only rewrites it when the credentials change.
    home.activation.provisionAtuin = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.python3}/bin/python3 ${./atuin-provision.py} "''${XDG_DATA_HOME:-$HOME/.local/share}/atuin" \
        ${lib.getExe decrypt} ${lib.getExe atuin} ${../../../secrets/atuin-key.age} ${../../../secrets/atuin-session.age} \
        || warnEcho "Atuin sync credentials were not provisioned"
    '';
  };
}
