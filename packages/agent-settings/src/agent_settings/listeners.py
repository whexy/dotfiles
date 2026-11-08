"""Loopback listeners an entry's endpoint is served on, checked before credentials go to them.

Another user on a shared host can bind a relay's port while the relay does
not hold it, and would then receive the API key and every prompt. Linux
reports each socket's owner in /proc/net/tcp{,6}, which every user can read.
"""

import os
from pathlib import Path

from agent_settings.catalog import Entry
from agent_settings.errors import SettingsError

_LISTEN = "0A"
# Addresses whose listener accepts connections to 127.0.0.1, as /proc spells
# them: 127.0.0.1 and 0.0.0.0 over IPv4; ::, ::ffff:127.0.0.1 and
# ::ffff:0.0.0.0 over IPv6 for dual-stack sockets.
_IPV4 = {"0100007F", "00000000"}
_IPV6 = {
    "00000000000000000000000000000000",
    "0000000000000000FFFF00000100007F",
    "0000000000000000FFFF000000000000",
}


def check_listeners(entry: Entry) -> None:
    """Fail unless every listener of the entry is held by this user alone."""
    for address in entry.get("listeners", []):
        host, _, port = address.rpartition(":")
        if host != "127.0.0.1" or not port.isdigit():
            raise SettingsError(f"{address}: only 127.0.0.1:<port> listeners can be checked")
        owners = _listening_owners(int(port))
        if not owners:
            raise SettingsError(f"nothing listens on {address}; is the tailnet relay running?")
        strangers = owners - {os.getuid()}
        if strangers:
            uids = ", ".join(str(uid) for uid in sorted(strangers))
            raise SettingsError(
                f"{address} is held by uid {uids}, not this user; refusing to send credentials"
            )


def _listening_owners(port: int) -> set[int]:
    """Owners of the listening sockets that accept connections to 127.0.0.1:port."""
    owners: set[int] = set()
    for table, addresses in (("tcp", _IPV4), ("tcp6", _IPV6)):
        try:
            lines = Path("/proc/net", table).read_text().splitlines()[1:]
        except FileNotFoundError:
            if table == "tcp":
                raise SettingsError("relay listeners can only be checked on Linux") from None
            continue
        for line in lines:
            # sl local_address rem_address st tx:rx tr:when retrnsmt uid ...
            fields = line.split()
            local, state, uid = fields[1], fields[3], fields[7]
            address, _, hex_port = local.partition(":")
            if state == _LISTEN and int(hex_port, 16) == port and address in addresses:
                owners.add(int(uid))
    return owners
