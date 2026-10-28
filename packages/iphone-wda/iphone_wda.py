"""Build, install, launch and stop WebDriverAgent on the phones in the config.

A runner launched here keeps serving after this process exits, on the phone's
Tailscale address only, so agents on any tailnet host can drive the phone with
no computer attached. Launching needs a host that reaches the phone's
developer services: a Mac paired with it, over USB or Wi-Fi.
"""

from __future__ import annotations

import argparse
import asyncio
import contextlib
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import NoReturn

CONFIG_PATH = (
    Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "iphone-wda/config.json"
)
DATA = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "iphone-wda"
DERIVED = DATA / "derived"
BUILT_APP = DERIVED / "Build/Products/Debug-iphoneos/WebDriverAgentRunner-Runner.app"

# The WebDriverAgent iPhone Use 0.3.15 pins; its client relies on this
# version's session settings.
WDA_COMMIT = "d17782422d55ff1e5e0ceb74eb1fd509cc0c35b6"
WDA_REPOSITORY = "https://github.com/appium/WebDriverAgent.git"

READY_TIMEOUT = 90


def fail(message: str) -> NoReturn:
    sys.exit(f"iphone-wda: {message}")


def load_config() -> dict:
    try:
        return json.loads(CONFIG_PATH.read_text())
    except FileNotFoundError:
        fail(f"{CONFIG_PATH} is missing; dotfiles.agents.iphoneUse writes it.")


def phone_config(config: dict, name: str) -> dict:
    phones = config["phones"]
    if name not in phones:
        fail(f"unknown phone {name!r}; configured: {', '.join(sorted(phones))}")
    return phones[name]


def runner_bundle(config: dict) -> str:
    return config["wda"]["bundleId"] + ".xctrunner"


def tailnet_ipv4(host: str) -> str:
    """The runner binds one address, so it and its clients agree on IPv4."""
    try:
        return socket.getaddrinfo(host, None, socket.AF_INET, socket.SOCK_STREAM)[0][4][0]
    except socket.gaierror:
        fail(f"{host} does not resolve; is the phone on the tailnet?")


def wda_status(host: str, port: int, timeout: float = 3.0) -> dict | None:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        url = f"http://{tailnet_ipv4(host)}:{port}/status"
        with opener.open(url, timeout=timeout) as response:
            return json.load(response).get("value") or {}
    except (OSError, ValueError, urllib.error.URLError):
        return None


async def visible_devices() -> list[dict]:
    """Phones reachable through usbmuxd, which on macOS includes Wi-Fi pairings."""
    from pymobiledevice3.exceptions import ConnectionFailedToUsbmuxdError
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.usbmux import list_devices

    try:
        listed = await list_devices()
    except ConnectionFailedToUsbmuxdError:
        fail(
            "usbmuxd is not running here. Run this on a Mac paired with the phone, "
            "or on a machine the phone is plugged into."
        )
    devices, seen = [], set()
    for device in listed:
        if device.serial in seen:
            continue
        seen.add(device.serial)
        try:
            async with await create_using_usbmux(
                serial=device.serial,
                connection_type=device.connection_type,
                autopair=False,
            ) as lockdown:
                info = lockdown.short_info
        except Exception as error:  # One unpaired device must not hide the rest.
            info = {"error": str(error)}
        devices.append({"udid": device.serial, "connection": device.connection_type, **info})
    return devices


async def find_udid(device_name: str) -> str:
    devices = await visible_devices()
    for device in devices:
        if device.get("DeviceName") == device_name:
            return device["udid"]
    names = ", ".join(repr(d.get("DeviceName")) for d in devices) or "none"
    fail(f"no visible device is named {device_name!r} (visible: {names}).")


@contextlib.asynccontextmanager
async def process_control(udid: str):
    from pymobiledevice3.remote.rsd_tunnel import PreferredRsdTunnel
    from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
    from pymobiledevice3.services.dvt.instruments.process_control import ProcessControl

    async with (
        PreferredRsdTunnel(serial=udid) as rsd,
        DvtProvider(rsd) as dvt,
        ProcessControl(dvt) as control,
    ):
        yield control


async def launch(config: dict, name: str) -> None:
    phone, wda = phone_config(config, name), config["wda"]
    address = tailnet_ipv4(phone["host"])
    udid = await find_udid(phone["deviceName"])
    environment = {
        "USE_IP": address,
        "USE_PORT": str(wda["port"]),
        "MJPEG_SERVER_PORT": str(wda["mjpegPort"]),
    }
    async with process_control(udid) as control:
        # iOS 27 ignores the runner's own press of Home to background itself,
        # so its server never starts unless it is launched in the background,
        # the way Xcode launches it.
        pid = await control.launch(
            bundle_id=runner_bundle(config),
            environment=environment,
            kill_existing=True,
            extra_options={"ActivateSuspended": True},
        )
    print(f"Launched WebDriverAgent on {name} (pid {pid}); waiting for {address}:{wda['port']}.")
    deadline = time.monotonic() + READY_TIMEOUT
    while time.monotonic() < deadline:
        status = wda_status(phone["host"], wda["port"])
        if status and status.get("ready") is True:
            print(f"{name} is ready.")
            return
        time.sleep(2)
    fail(
        f"{name} did not answer within {READY_TIMEOUT} s. Unlock the phone; if it asks "
        "for the passcode to allow UI automation, enter it, then launch again."
    )


async def stop(config: dict, name: str) -> None:
    phone = phone_config(config, name)
    udid = await find_udid(phone["deviceName"])
    async with process_control(udid) as control:
        pid = await control.process_identifier_for_bundle_identifier(runner_bundle(config))
        if pid:
            await control.kill(pid)
    print(
        f"Stopped WebDriverAgent on {name}."
        if pid
        else f"WebDriverAgent was not running on {name}."
    )


async def install(config: dict, name: str, app: Path) -> None:
    from pymobiledevice3.lockdown import create_using_usbmux
    from pymobiledevice3.services.installation_proxy import InstallationProxyService

    if not (app / "Info.plist").is_file():
        fail(f"{app} is not an app bundle; run `iphone-wda build` first.")
    phone = phone_config(config, name)
    udid = await find_udid(phone["deviceName"])
    async with await create_using_usbmux(serial=udid) as lockdown:
        await InstallationProxyService(lockdown=lockdown).install_from_local(app)
    print(f"Installed {app.name} on {name}. Launch it with `iphone-wda launch {name}`.")


def git(*args: str, source: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(source), *args], check=True, capture_output=True, text=True
    )


def fetch_source() -> Path:
    source = DATA / "WebDriverAgent"
    if not source.exists():
        source.mkdir(parents=True)
        git("init", "--quiet", source=source)
        git("remote", "add", "origin", WDA_REPOSITORY, source=source)
    head = subprocess.run(
        ["git", "-C", str(source), "rev-parse", "HEAD"], capture_output=True, text=True
    ).stdout.strip()
    if head != WDA_COMMIT:
        git("fetch", "--quiet", "--depth", "1", "origin", WDA_COMMIT, source=source)
        git("checkout", "--quiet", "--detach", "FETCH_HEAD", source=source)
    if git("status", "--porcelain", "--untracked-files=no", source=source).stdout.strip():
        fail(f"{source} has local changes; remove it to fetch a clean copy.")
    return source


def build(config: dict, register: str | None) -> None:
    if sys.platform != "darwin":
        fail("build needs macOS with Xcode.")
    wda = config["wda"]
    source = fetch_source()
    destination, registration = "generic/platform=iOS", []
    if register:
        # The team profile lists only registered devices; a new phone joins it
        # when Xcode builds for that device.
        udid = asyncio.run(find_udid(phone_config(config, register)["deviceName"]))
        destination, registration = f"id={udid}", ["-allowProvisioningDeviceRegistration"]
    built = subprocess.run(
        [
            "xcodebuild",
            "-project",
            str(source / "WebDriverAgent.xcodeproj"),
            "-scheme",
            "WebDriverAgentRunner",
            "-configuration",
            "Debug",
            "-destination",
            destination,
            "-derivedDataPath",
            str(DERIVED),
            "-allowProvisioningUpdates",
            *registration,
            f"DEVELOPMENT_TEAM={wda['teamId']}",
            "CODE_SIGN_STYLE=Automatic",
            f"PRODUCT_BUNDLE_IDENTIFIER={wda['bundleId']}",
            "build-for-testing",
        ],
    )
    if built.returncode != 0:
        # SSH sessions see the login keychain as locked, so codesign cannot
        # reach the signing key there.
        fail(
            "xcodebuild failed. If CodeSign reported errSecInternalComponent, run the "
            "build in a terminal on the Mac itself, not over SSH."
        )
    print(f"Built {BUILT_APP}. Install it with `iphone-wda install <phone>`.")


def status(config: dict, names: list[str]) -> None:
    port = config["wda"]["port"]
    for name in names or sorted(config["phones"]):
        value = wda_status(phone_config(config, name)["host"], port)
        if value is None:
            print(f"{name}: not answering")
        else:
            ios = (value.get("os") or {}).get("version", "?")
            build_version = (value.get("build") or {}).get("version", "?")
            state = "ready" if value.get("ready") else "not ready"
            print(f"{name}: {state} (iOS {ios}, WebDriverAgent {build_version})")


def main() -> None:
    parser = argparse.ArgumentParser(prog="iphone-wda", description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("devices", help="list phones this host reaches through usbmuxd")
    show = commands.add_parser("status", help="show whether each phone's runner answers")
    show.add_argument("phones", nargs="*")
    for command, text in (("launch", "start the runner on a phone"), ("stop", "stop it")):
        commands.add_parser(command, help=text).add_argument("phone")
    put = commands.add_parser("install", help="install the built runner on a phone")
    put.add_argument("phone")
    put.add_argument("--app", type=Path, default=BUILT_APP)
    make = commands.add_parser("build", help="build and sign the runner (macOS)")
    make.add_argument("--register", metavar="PHONE", help="add a new phone to the team profile")
    args = parser.parse_args()

    if args.command == "devices":
        for device in asyncio.run(visible_devices()):
            print(json.dumps(device, ensure_ascii=False))
        return
    config = load_config()
    if args.command == "status":
        status(config, args.phones)
    elif args.command == "launch":
        asyncio.run(launch(config, args.phone))
    elif args.command == "stop":
        asyncio.run(stop(config, args.phone))
    elif args.command == "install":
        asyncio.run(install(config, args.phone, args.app))
    elif args.command == "build":
        build(config, args.register)


if __name__ == "__main__":
    main()
