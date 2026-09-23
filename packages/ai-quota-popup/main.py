#!/usr/bin/env python3
"""Quota detail window shared by Waybar, Eww, and SketchyBar."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

from PySide6.QtCore import QCoreApplication, QLockFile, QObject, Property, QTimer, QUrl, Signal, Slot
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtGui import QCursor, QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow, QSGRendererInterface


RESOURCES = Path(os.environ.get("AI_QUOTA_POPUP_RESOURCES", Path(__file__).resolve().parent))
CONFIG = json.loads((RESOURCES / "config.json").read_text())
PROVIDERS = {provider["name"] for provider in CONFIG["providers"]}


def parse_time(value):
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def percentage(value):
    try:
        number = float(value)
        return max(0, min(100, number)) if math.isfinite(number) else None
    except (TypeError, ValueError):
        return None


def countdown(seconds):
    if seconds <= 0:
        return "now"
    minutes = max(1, math.ceil(seconds / 60))
    if minutes >= 2880:
        return f"{minutes // 1440}d {(minutes % 1440) // 60}h"
    if minutes >= 60:
        return f"{minutes // 60}h {minutes % 60:02d}m"
    return f"{minutes}m"


def project_meter(meter, now):
    remaining = percentage(meter.get("remaining"))
    reset = parse_time(meter.get("reset_at"))
    duration = meter.get("duration_seconds") or meter.get("span")
    try:
        duration = float(duration)
    except (TypeError, ValueError):
        duration = 0
    timed = bool(reset and math.isfinite(duration) and 0 < duration < 366 * 86400)
    start = reset.timestamp() - duration if timed else 0
    end = reset.timestamp() if timed else 0
    fraction = max(0, min(1, (now.timestamp() - start) / duration)) if timed else 0
    reset_text = (
        "Reset overdue" if end < now.timestamp() - 60 else
        "Resets now" if end <= now.timestamp() else
        "Resets in " + countdown(end - now.timestamp())
    ) if timed else (meter.get("reset_label") or "Reset unavailable")
    return {
        "label": str(meter.get("label") or "Window"),
        "remaining": round(remaining) if remaining is not None else None,
        "reset": reset_text,
        "timed": timed,
        "timeFraction": fraction,
        "startLabel": datetime.fromtimestamp(start, now.tzinfo).strftime("%b %d" if duration >= 86400 else "%H:%M") if timed else "",
        "endLabel": reset.astimezone(now.tzinfo).strftime("%b %d" if duration >= 86400 else "%H:%M") if timed else "",
    }


def project(raw, config=CONFIG, now=None):
    """Pure view projection; the jq filter owns the quota selection semantics."""
    now = now or datetime.now().astimezone()
    cards = []
    for provider in config["providers"]:
        record = raw.get(provider["name"], {"present": False})
        if not record.get("present"):
            continue
        accounts = []
        for account in record.get("accounts") or []:
            accounts.append({
                "name": str(account.get("name") or "Account"),
                "plan": str(account.get("plan") or account.get("subtitle") or ""),
                "error": str(account.get("error") or ""),
                "meters": [project_meter(meter, now) for meter in account.get("meters") or [] if meter],
            })
        cards.append({
            "id": provider["name"],
            "title": provider["title"],
            "logo": QUrl.fromLocalFile(str(RESOURCES / "logos" / (provider["name"] + ".png"))).toString(),
            "remaining": percentage(record.get("remaining")),
            "state": record.get("state") or "error",
            "accounts": accounts,
        })
    return cards


def fetch(config=CONFIG, fixture=None):
    if fixture:
        raw = Path(fixture).read_text()
    else:
        raw = subprocess.run(
            ["curl", "-fsS", "--max-time", "10", config["apiUrl"]],
            text=True, capture_output=True, timeout=12, check=True,
        ).stdout
        if len(raw) > 2_000_000:
            raise ValueError("Quota response is too large")
    parsed = json.loads(raw)
    if not isinstance(parsed, dict) or not isinstance(parsed.get("providers"), list):
        raise ValueError("Quota response has no providers")
    summaries = {"_updated_at": parsed.get("updated_at")}
    for provider in config["providers"]:
        result = subprocess.run(
            ["jq", "-c", "-f", str(RESOURCES / "summary.jq"), "--arg", "provider", provider["name"]],
            input=raw,
            text=True,
            capture_output=True,
            timeout=5,
            check=True,
        )
        summaries[provider["name"]] = json.loads(result.stdout)
    return summaries


class Controller(QObject):
    changed = Signal()
    fetched = Signal(object, str)

    def __init__(self, fixture=None, screenshot=False):
        super().__init__()
        self.fixture = fixture
        self.screenshot = screenshot
        self.window = None
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

    @Property(str, notify=changed)
    def payload(self):
        cards = sorted(self.cards, key=lambda card: card["id"] != self.selected)
        return json.dumps({
            "cards": cards,
            "selected": self.selected,
            "error": self.error,
            "stale": self.stale,
            "loadedAt": self.loaded_at,
            "loading": self.loading,
        })

    @Property(bool, constant=True)
    def screenshotMode(self):
        return self.screenshot

    @Slot()
    def hide(self):
        if self.window:
            self.window.hide()
        self.timer.stop()
        self.idle_timer.start()

    @Slot()
    def refresh(self):
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

    def toggle(self, provider, edge=None):
        if provider not in PROVIDERS:
            return
        if self.window.isVisible() and self.selected == provider:
            self.hide()
            return
        self.idle_timer.stop()
        self.selected = provider
        self.changed.emit()
        self.window.show()
        self.window.raise_()
        self.window.requestActivate()
        if sys.platform == "darwin":
            cursor = QCursor.pos()
            screen = QGuiApplication.screenAt(cursor) or QGuiApplication.primaryScreen()
            bounds = screen.availableGeometry()
            width, height = self.window.width(), self.window.height()
            x = max(bounds.left(), min(cursor.x() - width // 2, bounds.right() - width + 1))
            y = bounds.top() + 8 if edge == "top" else bounds.bottom() - height - 7
            self.window.setPosition(x, max(bounds.top(), y))
        self.timer.start()
        self.refresh()


def server_name():
    session = os.environ.get("XDG_SESSION_ID") or os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY") or "desktop"
    identity = f"{os.getuid()}:{os.environ.get('XDG_RUNTIME_DIR', '')}:{session}"
    return "ai-quota-popup-" + hashlib.sha256(identity.encode()).hexdigest()[:20]


def send_command(name, provider, edge=None):
    socket = QLocalSocket()
    socket.connectToServer(name)
    if not socket.waitForConnected(250):
        return False
    command = {"provider": provider, "version": str(RESOURCES), "edge": edge}
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
    parser.add_argument("--fixture", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--screenshot", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--serve", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.screenshot and not args.fixture:
        parser.error("--screenshot requires --fixture")
    name = server_name()
    selected = args.toggle or CONFIG["providers"][0]["name"]
    edge = os.environ.get("AI_QUOTA_BAR_EDGE", "bottom")
    if not args.serve and not args.screenshot:
        app = QCoreApplication(sys.argv)
        lock = QLockFile(str(Path(os.environ.get("XDG_RUNTIME_DIR", tempfile.gettempdir())) / (name + ".lock")))
        if not lock.tryLock(3000):
            raise RuntimeError("Could not acquire quota popup launch lock")
        try:
            if not send_command(name, selected, edge):
                command = [sys.executable, str(RESOURCES / "main.py"), "--serve", "--toggle", selected]
                if args.fixture:
                    command.extend(["--fixture", str(args.fixture.resolve())])
                subprocess.Popen(
                    command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, start_new_session=True,
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
    server = QLocalServer()
    server.setSocketOptions(QLocalServer.UserAccessOption)
    if not args.screenshot and not server.listen(name):
        for _ in range(20):
            if send_command(name, selected, edge):
                return 0
            time.sleep(0.05)
            if server.listen(name):
                break
        else:
            QLocalServer.removeServer(name)
            if not server.listen(name):
                raise RuntimeError(server.errorString())
    controller = Controller(fixture=args.fixture, screenshot=bool(args.screenshot))
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
                    controller.toggle(provider, command.get("edge"))
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
    controller.toggle(selected, edge)
    if args.screenshot:
        def save():
            if controller.loading:
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
