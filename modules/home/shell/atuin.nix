{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.shell;
  inherit (pkgs) atuin;
  relay = config.dotfiles.tailnetRelay;
  server = "https://atuin.at-basking.ts.net";

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
  provision = pkgs.writeText "atuin-provision.py" ''
    import os
    import pathlib
    import sqlite3
    import subprocess
    import sys

    root = pathlib.Path(sys.argv[1])
    identities = [path for path in ${builtins.toJSON (map toString config.age.identityPaths)} if os.access(path, os.R_OK)]
    if not identities:
        raise SystemExit("No readable agenix identity for the Atuin credentials")

    def decrypt(secret):
        flags = [flag for path in identities for flag in ("-i", path)]
        result = subprocess.run(
            ["${lib.getExe config.age.package}", "--decrypt", *flags, secret],
            stdout=subprocess.PIPE,
        )
        if result.returncode:
            raise SystemExit("Could not decrypt " + secret)
        return result.stdout

    key = decrypt("${../../../secrets/atuin-key.age}")
    token = decrypt("${../../../secrets/atuin-session.age}").decode().strip()
    if not key or not token:
        raise SystemExit("Atuin credentials are empty")
    key_path = root / "key"
    session_path = root / "session"
    if key_path.exists() and key_path.read_bytes() == key and session_path.exists() and session_path.read_bytes() == token.encode():
        sys.exit()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    if key_path.exists() and key_path.read_bytes() != key:
        # A host that used Atuin before the shared key has records encrypted
        # with its own key; rekey them so they stay readable and syncable.
        # rekey saves the new key only after the store is rewritten.
        subprocess.run(
            ["${lib.getExe atuin}", "store", "rekey", key.decode().strip()],
            env={**os.environ, "ATUIN_SESSION": os.environ.get("ATUIN_SESSION", "provision")},
            stdout=subprocess.DEVNULL,
            check=True,
        )
        if key_path.read_bytes() != key:
            raise SystemExit("Atuin rekey did not install the agenix key")

    def replace(name, data):
        import tempfile
        fd, tmp = tempfile.mkstemp(dir=root)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
            os.replace(tmp, root / name)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)

    if not key_path.exists():
        replace("key", key)
    # Newer clients migrate legacy files only once; update just the session,
    # preserving each host's identity, sync cursors, and migration metadata.
    meta = root / "meta.db"
    if meta.exists():
        with sqlite3.connect(meta, timeout=10) as db:
            if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='meta'").fetchone():
                db.execute(
                    "INSERT INTO meta (key,value,updated_at) VALUES ('session',?,strftime('%s','now')) "
                    "ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at",
                    (token,),
                )
    replace("session", token.encode())
  '';
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
      run ${pkgs.python3}/bin/python3 ${provision} "''${XDG_DATA_HOME:-$HOME/.local/share}/atuin" \
        || warnEcho "Atuin sync credentials were not provisioned"
    '';
  };
}
