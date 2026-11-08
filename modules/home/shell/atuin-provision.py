# Installs the shared Atuin key and sync session from agenix into Atuin's
# data directory. Usage: atuin-provision.py <data dir> <agenix-decrypt>
# <atuin> <key.age> <session.age>
import os
import pathlib
import sqlite3
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
decrypt_command, atuin, key_secret, session_secret = sys.argv[2:6]


def decrypt(secret):
    result = subprocess.run([decrypt_command, secret], stdout=subprocess.PIPE)
    if result.returncode:
        raise SystemExit("Could not decrypt " + secret)
    return result.stdout


key = decrypt(key_secret)
token = decrypt(session_secret).decode().strip()
if not key or not token:
    raise SystemExit("Atuin credentials are empty")
key_path = root / "key"
session_path = root / "session"
if (
    key_path.exists()
    and key_path.read_bytes() == key
    and session_path.exists()
    and session_path.read_bytes() == token.encode()
):
    sys.exit()
root.mkdir(parents=True, exist_ok=True, mode=0o700)
if key_path.exists() and key_path.read_bytes() != key:
    # A host that used Atuin before the shared key has records encrypted
    # with its own key; rekey them so they stay readable and syncable.
    # rekey saves the new key only after the store is rewritten.
    subprocess.run(
        [atuin, "store", "rekey", key.decode().strip()],
        env={**os.environ, "ATUIN_SESSION": os.environ.get("ATUIN_SESSION", "provision")},
        stdout=subprocess.DEVNULL,
        check=True,
    )
    if key_path.read_bytes() != key:
        raise SystemExit("Atuin rekey did not install the agenix key")


def replace(name, data):
    fd, tmp_name = tempfile.mkstemp(dir=root)
    tmp = pathlib.Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        tmp.replace(root / name)
    finally:
        tmp.unlink(missing_ok=True)


if not key_path.exists():
    replace("key", key)
# Newer clients migrate legacy files only once; update just the session,
# preserving each host's identity, sync cursors, and migration metadata.
meta = root / "meta.db"
if meta.exists():
    with sqlite3.connect(meta, timeout=10) as db:
        if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='meta'").fetchone():
            db.execute(
                "INSERT INTO meta (key,value,updated_at) "
                "VALUES ('session',?,strftime('%s','now')) "
                "ON CONFLICT(key) DO UPDATE "
                "SET value=excluded.value,updated_at=excluded.updated_at",
                (token,),
            )
replace("session", token.encode())
