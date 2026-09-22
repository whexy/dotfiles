{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.shell;
  inherit (pkgs) atuin;
  provision = pkgs.writeText "atuin-provision.py" ''
    import fcntl
    import os
    import pathlib
    import sqlite3
    import subprocess
    import sys

    root = pathlib.Path(sys.argv[1])
    key = pathlib.Path(sys.argv[2]).read_bytes()
    token = pathlib.Path(sys.argv[3]).read_text().strip()
    if not key or not token:
        raise SystemExit("Atuin credentials are empty; check agenix decryption")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Every shell hook invokes the wrapper, so concurrent shells must not
    # rekey the store twice.
    lock = open(root / ".provision.lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    key_path = root / "key"
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
  wrapped = pkgs.symlinkJoin {
    name = "atuin-provisioned-${atuin.version}";
    paths = [ atuin ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm "$out/bin/atuin"
      makeWrapper ${lib.getExe atuin} "$out/bin/atuin" \
        --run ${lib.escapeShellArg ''
          _atuin_root="''${XDG_DATA_HOME:-$HOME/.local/share}/atuin"
          _atuin_key="${config.age.secrets.atuin-key.path}"
          _atuin_session="${config.age.secrets.atuin-session.path}"
          if [ -s "$_atuin_key" ] && [ -s "$_atuin_session" ]; then
            if ! ${pkgs.diffutils}/bin/cmp -s "$_atuin_key" "$_atuin_root/key" || ! ${pkgs.diffutils}/bin/cmp -s "$_atuin_session" "$_atuin_root/session"; then
              ${pkgs.python3}/bin/python3 ${provision} "$_atuin_root" "$_atuin_key" "$_atuin_session" || exit 1
            fi
          fi
          unset _atuin_root _atuin_key _atuin_session
        ''}
    '';
    meta.mainProgram = "atuin";
  };
in
{
  config = lib.mkIf (cfg.zsh.devExtras || cfg.nushell.devExtras) {
    age.secrets = {
      atuin-key.file = ../../../secrets/atuin-key.age;
      atuin-session.file = ../../../secrets/atuin-session.age;
    };
    programs.atuin.package = wrapped;
  };
}
