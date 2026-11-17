#!/usr/bin/env python3
"""Quota detail window shared by Waybar, Eww, and SketchyBar."""

import argparse
import ctypes
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from urllib.parse import urlencode

from PySide6.QtCore import (
    Property,
    QCoreApplication,
    QLockFile,
    QObject,
    QSettings,
    QTimer,
    QUrl,
    Signal,
    Slot,
)
from PySide6.QtGui import QCursor, QGuiApplication
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow, QSGRendererInterface

RESOURCES = Path(os.environ.get("AI_QUOTA_POPUP_RESOURCES", Path(__file__).resolve().parent))
CONFIG = json.loads((RESOURCES / "config.json").read_text())
PROVIDERS = {provider["name"] for provider in CONFIG["providers"]}
VIEWS = ("quota", "usage")
# What the range picker offers before the first answer names the ranges the
# server keeps enough data for.
USAGE_RANGES = ["24h", "7d", "30d"]
DEFAULT_RANGE = "7d"


def parse_time(value):
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)
    except ValueError:
        return None


def usage(value):
    try:
        number = float(value)
        return number if math.isfinite(number) and number >= 0 else None
    except (TypeError, ValueError):
        return None


def countdown(seconds):
    if seconds <= 0:
        return "Reset pending"
    seconds = int(seconds)
    if seconds >= 86400:
        return f"{seconds // 86400}d {(seconds % 86400) // 3600}h"
    if seconds >= 3600:
        return f"{seconds // 3600}h {(seconds % 3600) // 60}m"
    return f"{max(1, seconds // 60)}m"


def display_label(label):
    hours = re.fullmatch(r"(\d+)h", label)
    minutes = re.fullmatch(r"(\d+)m", label)
    if hours:
        return f"{hours[1]}-hour window"
    if minutes:
        return f"{minutes[1]}-minute window"
    return " ".join(word[:1].upper() + word[1:] for word in label.split(" "))


def axis_label(moment, weekly):
    return moment.strftime("%a") if weekly else f"{moment.hour % 12 or 12}:{moment.minute:02d}"


def project_meter(meter, observed, now):
    """Mirror QuotaWidget's timeline: usage and elapsed time share one axis."""
    used = usage(meter.get("percent"))
    reset = parse_time(meter.get("reset_at"))
    try:
        duration = float(meter.get("duration_seconds") or 0)
    except (TypeError, ValueError):
        duration = 0
    timed = bool(reset and math.isfinite(duration) and 0 < duration < 366 * 86400)
    start = reset.timestamp() - duration if timed else 0
    expired = bool(reset and reset <= now)
    elapsed = (
        max(0, min(1, (now.timestamp() - start) / duration)) if timed and not expired else None
    )

    # Linear pace from the observation time: an aging sample isn't new usage.
    projection = None
    if (
        timed
        and used is not None
        and observed
        and now < reset
        and observed <= now + timedelta(seconds=60)
        and (now - observed).total_seconds() <= 1800
        and observed < reset
        and observed.timestamp() - start >= max(300, duration * 0.01)
    ):
        projection = used / ((observed.timestamp() - start) / duration)

    divisions = 7 if duration > 86400 else 4
    axis = (
        [
            {
                "fraction": index / divisions,
                "label": axis_label(
                    datetime.fromtimestamp(start + duration * index / divisions, now.tzinfo),
                    duration > 86400,
                ),
            }
            for index in range(divisions + 1)
        ]
        if timed
        else []
    )
    return {
        "label": display_label(str(meter.get("label") or "Window")),
        "raw_label": str(meter.get("label") or "").lower(),
        "used": used,
        "fraction": min(1, (used or 0) / 100),
        "countdown": countdown((reset - now).total_seconds()) if reset else "Idle",
        "elapsed": elapsed,
        "projection": projection,
        "projectionFraction": min(1, projection / 100) if projection is not None else None,
        "tint": "muted"
        if expired
        else "amber"
        if (projection if projection is not None else used or 0) > 100
        else "green",
        "axis": axis,
    }


def project_account(account, fallback_observed, now):
    observed = parse_time(account.get("observed_at")) or fallback_observed
    error = str(account.get("error") or "")
    meters = [
        project_meter(meter, None if error else observed, now)
        for meter in account.get("meters") or []
        if meter
    ]
    preferred = next(
        (m for m in meters if m["raw_label"] == "weekly"), meters[0] if meters else None
    )
    forecast = None
    if not error and preferred and preferred["projection"] is not None:
        over = preferred["projection"] > 100
        forecast = {
            "text": "Pace may exceed this window" if over else "Room to breathe",
            "value": f"~{round(preferred['projection'])}% at reset",
            "tint": "amber" if over else "green",
        }
    return {
        "name": str(account.get("name") or "Account"),
        "plan": str(account.get("plan") or account.get("subtitle") or account.get("name") or ""),
        "headline": preferred["used"] if preferred else None,
        "error": error,
        "meters": meters,
        "forecast": forecast,
    }


def project(raw, config=CONFIG, now=None):
    """Pure view projection; the jq filter owns the quota selection semantics."""
    now = now or datetime.now().astimezone()
    updated = parse_time(raw.get("_updated_at"))
    cards = []
    for provider in config["providers"]:
        record = raw.get(provider["name"], {"present": False})
        if not record.get("present"):
            continue
        cards.append(
            {
                "id": provider["name"],
                "title": provider["title"],
                "logo": QUrl.fromLocalFile(
                    str(RESOURCES / "logos" / (provider["name"] + ".png"))
                ).toString(),
                "accounts": [
                    project_account(account, updated, now)
                    for account in record.get("accounts") or []
                ],
            }
        )
    return cards


def fetch(config=CONFIG, fixture=None):
    if fixture:
        raw = Path(fixture).read_text()
    else:
        raw = subprocess.run(
            ["curl", "-fsS", "--max-time", "10", config["apiUrl"]],
            text=True,
            capture_output=True,
            timeout=12,
            check=True,
        ).stdout
        if len(raw) > 2_000_000:
            raise ValueError("Quota response is too large")
    parsed = json.loads(raw)
    if not isinstance(parsed, dict) or not isinstance(parsed.get("providers"), list):
        raise ValueError("Quota response has no providers")
    summaries = {"_updated_at": parsed.get("updated_at")}
    for provider in config["providers"]:
        result = subprocess.run(
            [
                "jq",
                "-c",
                "-f",
                str(RESOURCES / "summary.jq"),
                "--arg",
                "provider",
                provider["name"],
            ],
            input=raw,
            text=True,
            capture_output=True,
            timeout=5,
            check=True,
        )
        summaries[provider["name"]] = json.loads(result.stdout)
    return summaries


def local_zone():
    """The IANA name of the local zone, which /api/usage buckets days in."""
    name = r"[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+)*"
    zone = os.environ.get("TZ", "").lstrip(":")
    if re.fullmatch(name, zone):
        return zone
    # Follow /etc/localtime one link at a time: macOS resolves its zoneinfo
    # directory to zoneinfo.default, and NixOS ends in the store.
    path = zone if zone.startswith("/") else "/etc/localtime"
    for _ in range(8):
        match = re.search(rf"zoneinfo(?:\.default)?/(?:posix/|right/)?({name})$", path)
        if match:
            return match[1]
        try:
            link = Path(path)
            path = str(link.parent / link.readlink())
        except OSError:
            break
    return "UTC"


def count(value):
    number = usage(value)
    return number if number is not None else 0


def compact(value):
    value = count(value)
    for size, suffix in ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")):
        if value >= size * 0.9995:
            scaled = value / size
            text = f"{scaled:.0f}" if scaled >= 99.95 else f"{scaled:.1f}".removesuffix(".0")
            return text + suffix
    return f"{value:.0f}"


def money(value):
    return f"${count(value):,.2f}"


def share(part, total):
    percent = 100 * count(part) / total if total else 0
    if percent == 0:
        return "0%"
    return "<0.1%" if percent < 0.1 else f"{percent:.1f}%"


def nice_ceiling(value):
    if value <= 0:
        return 1
    magnitude = 10 ** math.floor(math.log10(value))
    steps = (1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10)
    return next(step * magnitude for step in steps if step * magnitude >= value)


def point_time(point, step):
    if step == "hour":
        moment = parse_time(point)
        return moment.astimezone() if moment else None
    try:
        return date.fromisoformat(point)
    except (TypeError, ValueError):
        return None


def day_label(moment):
    return f"{moment:%b} {moment.day}"


def project_usage(raw):
    """View projection of /api/usage: totals, a stacked chart, and the groups."""
    if not isinstance(raw, dict) or not isinstance(raw.get("totals"), dict):
        raise ValueError("Usage response has no totals")
    span = raw.get("range") if isinstance(raw.get("range"), dict) else {}
    step = span.get("step")
    priced = bool((raw.get("pricing") or {}).get("enabled"))
    totals = raw["totals"]
    processed = count(totals.get("processed"))
    groups = [g for g in raw.get("groups") or [] if isinstance(g, dict)]
    points = [p for p in raw.get("points") or [] if isinstance(p, dict)]

    moments = [point_time(p.get("point"), step) for p in points]
    daily = step != "hour"
    named_days = daily and len(points) <= 7

    def tick(moment):
        if moment is None:
            return ""
        if not daily:
            return f"{moment:%H}:00"
        return f"{moment:%a}" if named_days else day_label(moment)

    def readout(moment):
        if moment is None:
            return ""
        if daily:
            return f"{moment:%a} {day_label(moment)}"
        return f"{day_label(moment)}, {moment:%H}:00"

    peak = nice_ceiling(max((count(p.get("processed")) for p in points), default=0))
    bars = []
    for index, point in enumerate(points):
        segments = []
        # Largest group at the bottom; groups arrive sorted largest first.
        for group in reversed(groups):
            series = group.get("series_tokens") or []
            value = count(series[index]) if index < len(series) else 0
            if value > 0:
                segments.append({"color": group.get("color") or 0, "fraction": value / peak})
        detail = f"{compact(point.get('processed'))} tokens"
        if priced:
            detail += f", {money(point.get('cost'))}"
        bars.append(
            {
                "segments": segments,
                "readout": f"{readout(moments[index])}: {detail}",
            }
        )
    marks = min(len(points), 5 if daily and not named_days else 7 if daily else 5)
    ticks = sorted(
        {round(i * (len(points) - 1) / (marks - 1)) for i in range(marks)} if marks > 1 else {0}
    )

    start, end = parse_time(span.get("from")), parse_time(span.get("to"))
    if not daily:
        period = "Past 24 hours"
    elif start and end:
        last = (end - timedelta(seconds=1)).astimezone()
        period = f"{day_label(start.astimezone())} to {day_label(last)}"
    else:
        period = ""

    activity = [f"{int(count(totals.get('sessions'))):,} sessions"]
    activity.append(f"{int(count(totals.get('requests'))):,} requests")
    if count(totals.get("failed")):
        activity.append(f"{int(count(totals.get('failed'))):,} failed")

    return {
        "range": str(span.get("key") or ""),
        "ranges": [r for r in span.get("ranges") or [] if isinstance(r, str)] or USAGE_RANGES,
        "period": period,
        "processed": compact(processed),
        "cost": money(totals.get("cost")) if priced else "",
        "activity": ", ".join(activity),
        "chartTitle": "Daily processed tokens" if daily else "Hourly processed tokens",
        "peak": compact(peak),
        "half": compact(peak / 2),
        "bars": bars,
        "ticks": [{"index": i, "label": tick(moments[i])} for i in ticks if i < len(points)],
        "groups": [
            {
                "label": str(group.get("label") or "Other"),
                "detail": str(group.get("detail") or ""),
                "color": group.get("color") or 0,
                "tokens": compact(group.get("processed")),
                "fraction": count(group.get("processed")) / processed if processed else 0,
                "summary": f"{share(group.get('processed'), processed)} of tokens"
                + (f", {money(group.get('cost'))}" if priced else ""),
            }
            for group in groups
        ],
        "generatedAt": str(raw.get("generated_at") or ""),
    }


class UsageError(Exception):
    pass


def fetch_usage(range_key, config=CONFIG, fixture=None):
    if fixture:
        return project_usage(json.loads(Path(fixture).read_text()))
    query = urlencode({"range": range_key, "group": "family", "tz": local_zone()})
    result = subprocess.run(
        [
            "curl",
            "-sS",
            "--max-time",
            "10",
            "--max-filesize",
            "4000000",
            "-w",
            "\n%{http_code}",
            f"{config['usageUrl']}?{query}",
        ],
        text=True,
        capture_output=True,
        timeout=12,
        check=True,
    )
    body, _, status = result.stdout.rpartition("\n")
    if status != "200":
        try:
            message = json.loads(body).get("error")
        except (ValueError, AttributeError):
            message = None
        raise UsageError(str(message or f"HTTP {status}"))
    return project_usage(json.loads(body))


class Controller(QObject):
    changed = Signal()
    fetched = Signal(object, str)
    usage_fetched = Signal(str, object, str)

    def __init__(self, fixture=None, usage_fixture=None, screenshot=False):
        super().__init__()
        self.fixture = fixture
        self.usage_fixture = usage_fixture
        self.screenshot = screenshot
        self.settings = None if screenshot else QSettings("ai-quota-popup", "ai-quota-popup")
        self.view = "quota"
        stored = self.settings.value("usageRange") if self.settings else None
        self.range = stored if isinstance(stored, str) and stored else DEFAULT_RANGE
        self.usage = {}
        self.usage_errors = {}
        self.usage_loading = set()
        self.ranges = USAGE_RANGES
        self.window = None
        self.anchor = None
        self.edge = None
        self.selected = ""
        self.cards = []
        self.error = ""
        self.stale = False
        self.loaded_at = ""
        self.loading = False
        self.timer = QTimer(self)
        self.timer.setInterval(CONFIG["updateInterval"] * 1000)
        self.timer.timeout.connect(self.refresh)
        self.idle_timer = QTimer(self)
        self.idle_timer.setSingleShot(True)
        self.idle_timer.setInterval(60_000)
        self.idle_timer.timeout.connect(QCoreApplication.quit)
        self.fetched.connect(self._on_fetched)
        self.usage_fetched.connect(self._on_usage_fetched)

    @Property(str, notify=changed)
    def payload(self):
        return json.dumps(
            {
                "cards": [
                    {"title": card["title"], "logo": card["logo"], **account}
                    for card in self.cards
                    if card["id"] == self.selected
                    for account in card["accounts"]
                ],
                "error": self.error,
                "stale": self.stale,
                "loadedAt": self.loaded_at,
                "loading": self.loading,
                "view": self.view,
                "range": self.range,
                "ranges": self.ranges,
                "usage": self.usage.get(self.range),
                "usageError": self.usage_errors.get(self.range, ""),
                "usageLoading": self.range in self.usage_loading,
            }
        )

    @Property(bool, constant=True)
    def screenshotMode(self):
        return self.screenshot

    @Slot()
    def hide(self):
        if self.window:
            self.window.hide()
        self.timer.stop()
        self.idle_timer.start()

    @Slot(str)
    def setView(self, view):
        if view in VIEWS and view != self.view:
            self.view = view
            self.changed.emit()
            if view == "usage":
                self.refresh_usage()

    @Slot(str)
    def setRange(self, range_key):
        if not re.fullmatch(r"[0-9]+[a-z]", range_key) or range_key == self.range:
            return
        self.range = range_key
        if self.settings:
            self.settings.setValue("usageRange", range_key)
        self.changed.emit()
        self.refresh_usage()

    def busy(self):
        return self.loading or bool(self.usage_loading)

    def refresh_usage(self):
        range_key = self.range
        if range_key in self.usage_loading:
            return
        self.usage_loading.add(range_key)
        self.changed.emit()

        def worker():
            try:
                result = fetch_usage(range_key, fixture=self.usage_fixture)
                self.usage_fetched.emit(range_key, result, "")
            except UsageError as exc:
                self.usage_fetched.emit(range_key, None, f"Usage is unavailable: {exc}")
            except (OSError, ValueError, subprocess.SubprocessError, UnicodeError):
                self.usage_fetched.emit(range_key, None, "Could not refresh usage")

        threading.Thread(target=worker, daemon=True).start()

    @Slot(str, object, str)
    def _on_usage_fetched(self, range_key, result, error):
        self.usage_loading.discard(range_key)
        if error:
            self.usage_errors[range_key] = error
        else:
            self.usage[range_key] = result
            self.usage_errors.pop(range_key, None)
            self.ranges = result["ranges"]
        self.changed.emit()

    @Slot()
    def refresh(self):
        if self.view == "usage":
            self.refresh_usage()
        if self.loading:
            return
        self.loading = True
        self.changed.emit()

        def worker():
            try:
                result = fetch(fixture=self.fixture)
                self.fetched.emit(result, "")
            except (OSError, ValueError, subprocess.SubprocessError, UnicodeError) as exc:
                self.fetched.emit(None, str(exc))

        threading.Thread(target=worker, daemon=True).start()

    @Slot(object, str)
    def _on_fetched(self, result, error):
        self.loading = False
        if error:
            self.error = "Could not refresh quota"
            self.stale = bool(self.cards)
        else:
            now = datetime.now().astimezone()
            observed = parse_time(result.get("_updated_at")) or now
            self.cards = project(result, now=now)
            observations = [observed]
            for record in result.values():
                if isinstance(record, dict):
                    for account in record.get("accounts") or []:
                        account_time = parse_time(account.get("observed_at"))
                        if account_time:
                            observations.append(account_time)
            oldest = min(observations)
            self.loaded_at = oldest.astimezone().strftime("%b %d, %H:%M")
            self.stale = (now - oldest).total_seconds() > max(60, 2 * CONFIG["updateInterval"])
            self.error = "Quota data has not updated" if self.stale else ""
        self.changed.emit()

    @Slot()
    def place(self):
        """Keep the window against the bar edge as its content height changes."""
        if sys.platform != "darwin" or self.anchor is None:
            return
        screen = QGuiApplication.screenAt(self.anchor) or QGuiApplication.primaryScreen()
        bounds = screen.availableGeometry()
        width, height = self.window.width(), self.window.height()
        x = max(bounds.left(), min(self.anchor.x() - width // 2, bounds.right() - width + 1))
        y = bounds.top() + 8 if self.edge == "top" else bounds.bottom() - height - 7
        self.window.setPosition(x, max(bounds.top(), y))

    def toggle(self, provider, edge=None, view=None):
        if provider not in PROVIDERS:
            return
        view = view if view in VIEWS else None
        if self.window.isVisible() and self.selected == provider and view in (None, self.view):
            self.hide()
            return
        self.idle_timer.stop()
        # Usage covers every provider; a click on another provider's pill asks
        # about that provider's quota.
        if view:
            self.view = view
        elif provider != self.selected:
            self.view = "quota"
        self.selected = provider
        self.changed.emit()
        self.window.show()
        self.window.raise_()
        self.window.requestActivate()
        self.anchor = QCursor.pos()
        self.edge = edge
        self.place()
        self.timer.start()
        self.refresh()


def hide_dock_icon():
    # Qt promotes bundle-less executables to regular Dock apps while constructing
    # QGuiApplication; the accessory policy drops the Dock icon but keeps focus.
    objc = ctypes.cdll.LoadLibrary("/usr/lib/libobjc.A.dylib")
    objc.objc_getClass.restype = ctypes.c_void_p
    objc.sel_registerName.restype = ctypes.c_void_p
    get = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)(
        ("objc_msgSend", objc)
    )
    set_policy = ctypes.CFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_long)(
        ("objc_msgSend", objc)
    )
    ns_app = get(objc.objc_getClass(b"NSApplication"), objc.sel_registerName(b"sharedApplication"))
    set_policy(
        ns_app, objc.sel_registerName(b"setActivationPolicy:"), 1
    )  # NSApplicationActivationPolicyAccessory


def server_name():
    session = (
        os.environ.get("XDG_SESSION_ID")
        or os.environ.get("WAYLAND_DISPLAY")
        or os.environ.get("DISPLAY")
        or "desktop"
    )
    identity = f"{os.getuid()}:{os.environ.get('XDG_RUNTIME_DIR', '')}:{session}"
    return "ai-quota-popup-" + hashlib.sha256(identity.encode()).hexdigest()[:20]


def send_command(name, provider, edge=None, view=None):
    socket = QLocalSocket()
    socket.connectToServer(name)
    if not socket.waitForConnected(250):
        return False
    command = {"provider": provider, "version": str(RESOURCES), "edge": edge, "view": view}
    socket.write((json.dumps(command) + "\n").encode())
    socket.flush()
    if not socket.waitForReadyRead(500):
        return False
    accepted = bytes(socket.readAll()).strip() == b"ok"
    socket.disconnectFromServer()
    return accepted


def main():
    parser = argparse.ArgumentParser(description="Unified quota detail popup")
    parser.add_argument("--toggle", choices=sorted(PROVIDERS), metavar="PROVIDER")
    parser.add_argument("--view", choices=VIEWS, help="open on quota or usage")
    parser.add_argument("--fixture", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--usage-fixture", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--screenshot", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--serve", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    name = server_name()
    selected = args.toggle or CONFIG["providers"][0]["name"]
    edge = os.environ.get("AI_QUOTA_BAR_EDGE", "bottom")
    if not args.serve and not args.screenshot:
        app = QCoreApplication(sys.argv)
        lock = QLockFile(
            str(Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir())) / (name + ".lock"))
        )
        if not lock.tryLock(3000):
            raise RuntimeError("Could not acquire quota popup launch lock")
        try:
            if not send_command(name, selected, edge, args.view):
                command = [
                    sys.executable,
                    str(RESOURCES / "main.py"),
                    "--serve",
                    "--toggle",
                    selected,
                ]
                if args.view:
                    command.extend(["--view", args.view])
                if args.fixture:
                    command.extend(["--fixture", str(args.fixture.resolve())])
                if args.usage_fixture:
                    command.extend(["--usage-fixture", str(args.usage_fixture.resolve())])
                subprocess.Popen(
                    command,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    if send_command(name, "__ping__", edge):
                        break
                    time.sleep(0.05)
                else:
                    raise RuntimeError("Quota popup did not start")
        finally:
            lock.unlock()
        return 0
    if args.screenshot:
        QQuickWindow.setGraphicsApi(QSGRendererInterface.Software)
    app = QGuiApplication(sys.argv)
    app.setApplicationName("ai-quota-popup")
    app.setDesktopFileName("ai-quota-popup")
    app.setQuitOnLastWindowClosed(False)
    if sys.platform == "darwin":
        hide_dock_icon()
    server = QLocalServer()
    server.setSocketOptions(QLocalServer.UserAccessOption)
    if not args.screenshot and not server.listen(name):
        for _ in range(20):
            if send_command(name, selected, edge, args.view):
                return 0
            time.sleep(0.05)
            if server.listen(name):
                break
        else:
            QLocalServer.removeServer(name)
            if not server.listen(name):
                raise RuntimeError(server.errorString())
    controller = Controller(
        fixture=args.fixture,
        usage_fixture=args.usage_fixture,
        screenshot=bool(args.screenshot),
    )
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("bridge", controller)
    engine.load(QUrl.fromLocalFile(str(RESOURCES / "view.qml")))
    if not engine.rootObjects():
        return 1
    controller.window = engine.rootObjects()[0]

    def accept():
        while server.hasPendingConnections():
            socket = server.nextPendingConnection()
            socket.waitForReadyRead(500)
            try:
                command = json.loads(bytes(socket.readAll()))
            except (ValueError, TypeError):
                command = {}
            restart = command.get("version") != str(RESOURCES)
            if not restart:
                provider = command.get("provider")
                if provider in PROVIDERS:
                    controller.toggle(provider, command.get("edge"), command.get("view"))
            socket.write(b"restart" if restart else b"ok")
            socket.flush()
            socket.waitForBytesWritten(250)
            socket.disconnectFromServer()
            socket.deleteLater()
            if restart:
                controller.hide()
                server.close()
                app.exit(0)

    server.newConnection.connect(accept)
    controller.toggle(selected, edge, args.view)
    if args.screenshot:

        def save():
            if controller.busy():
                QTimer.singleShot(100, save)
                return
            image = controller.window.grabWindow()
            if image.isNull() or not image.save(str(args.screenshot)):
                print("Could not render screenshot", file=sys.stderr)
                app.exit(1)
            else:
                app.exit(0)

        QTimer.singleShot(700, save)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
