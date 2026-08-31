{ pkgs }:

pkgs.writers.writePython3Bin "motd"
  {
    flakeIgnore = [
      "E501" # long lines
      "W503" # line break before binary operator
    ];
  }
  ''
    """Render a compact, responsive system dashboard for interactive shells."""

    import json
    import os
    import platform
    import re
    import shutil
    import socket
    import subprocess
    import sys
    from datetime import datetime

    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN = "\033[36m"
    WHITE = "\033[37m"
    GRAY = "\033[90m"

    ANSI_RE = re.compile(r"\033\[[0-9;]*m")
    COLOR_MODE = os.environ.get("MOTD_COLOR", "auto").lower()
    COLOR = (
        "NO_COLOR" not in os.environ
        and os.environ.get("TERM") != "dumb"
        and (COLOR_MODE == "always" or (COLOR_MODE != "never" and sys.stdout.isatty()))
    )


    def paint(text: str, *codes: str) -> str:
        if not COLOR or not codes:
            return str(text)
        return "".join(codes) + str(text) + RESET


    def visible_len(text: str) -> int:
        return len(ANSI_RE.sub("", text))


    def truncate(text: str, width: int) -> str:
        if visible_len(text) <= width:
            return text
        if width <= 1:
            return "…"[:width]

        result = []
        visible = 0
        position = 0
        for match in ANSI_RE.finditer(text):
            plain = text[position:match.start()]
            remaining = width - 1 - visible
            if len(plain) > remaining:
                result.append(plain[:remaining])
                visible += remaining
                break
            result.append(plain)
            visible += len(plain)
            result.append(match.group(0))
            position = match.end()
        else:
            remaining = width - 1 - visible
            result.append(text[position:position + remaining])

        return "".join(result) + "…" + (RESET if COLOR else "")


    def fit(text: str, width: int) -> str:
        text = truncate(text, width)
        return text + " " * max(0, width - visible_len(text))


    def human_bytes(value: float) -> str:
        units = ["B", "KiB", "MiB", "GiB", "TiB"]
        value = float(value)
        for unit in units:
            if value < 1024.0 or unit == units[-1]:
                if unit in ("B", "KiB", "MiB"):
                    return "%.0f %s" % (value, unit)
                return "%.1f %s" % (value, unit)
            value /= 1024.0
        return "unknown"


    def severity_color(pct: float) -> str:
        if pct >= 90:
            return RED
        if pct >= 75:
            return YELLOW
        return GREEN


    def meter(pct: float, width: int = 6) -> str:
        pct = max(0.0, min(100.0, pct))
        filled = int(round(width * pct / 100.0))
        bar = paint("━" * filled, severity_color(pct)) + paint("─" * (width - filled), GRAY)
        return "%s %s" % (bar, paint("%2.0f%%" % pct, severity_color(pct), BOLD))


    def command(args, timeout=0.3):
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
            if result.returncode == 0:
                return result.stdout.strip()
        except Exception:
            pass
        return ""


    def get_system():
        system = platform.system()
        os_name = system
        if os.path.exists("/etc/os-release"):
            try:
                with open("/etc/os-release", encoding="utf-8") as file:
                    for line in file:
                        if line.startswith("PRETTY_NAME="):
                            os_name = line.split("=", 1)[1].strip().strip("\"'")
                            break
            except Exception:
                pass
        elif system == "Darwin":
            version = platform.mac_ver()[0]
            os_name = "macOS " + version if version else "macOS"

        kernel = "%s %s · %s" % (system, platform.release(), platform.machine())
        return socket.gethostname().split(".")[0], os_name, kernel


    def get_uptime():
        if os.path.exists("/proc/uptime"):
            try:
                with open("/proc/uptime", encoding="utf-8") as file:
                    seconds = int(float(file.readline().split()[0]))
                days, remainder = divmod(seconds, 86400)
                hours, remainder = divmod(remainder, 3600)
                minutes = remainder // 60
                parts = []
                if days:
                    parts.append("%dd" % days)
                if hours:
                    parts.append("%dh" % hours)
                parts.append("%dm" % minutes)
                return " ".join(parts)
            except Exception:
                pass

        output = command(["uptime"], timeout=0.4)
        match = re.search(r"up\s+(.*?),\s+\d+\s+users?", output)
        return match.group(1).strip() if match else "unknown"


    def get_load():
        try:
            one, five, fifteen = os.getloadavg()
            cores = os.cpu_count() or 1
            pressure = one / cores * 100.0
            text = "%.2f  %.2f  %.2f" % (one, five, fifteen)
            return paint(text, severity_color(pressure)), pressure
        except Exception:
            return "unknown", None


    def linux_memory():
        if not os.path.exists("/proc/meminfo"):
            return None
        try:
            values = {}
            with open("/proc/meminfo", encoding="utf-8") as file:
                for line in file:
                    key, value = line.split(":", 1)
                    values[key] = int(value.split()[0]) * 1024
            total = values["MemTotal"]
            available = values.get("MemAvailable", values.get("MemFree", 0))
            return max(0, total - available), total
        except Exception:
            return None


    def darwin_memory():
        if platform.system() != "Darwin":
            return None
        try:
            total = int(command(["sysctl", "-n", "hw.memsize"]))
            output = command(["vm_stat"], timeout=0.4)
            page_match = re.search(r"page size of (\d+) bytes", output)
            page_size = int(page_match.group(1)) if page_match else 4096
            pages = {}
            for line in output.splitlines():
                match = re.match(r"([^:]+):\s+(\d+)\.", line)
                if match:
                    pages[match.group(1)] = int(match.group(2))
            available_pages = sum(
                pages.get(name, 0)
                for name in ("Pages free", "Pages inactive", "Pages speculative")
            )
            return max(0, total - available_pages * page_size), total
        except Exception:
            return None


    def get_memory():
        usage = linux_memory() or darwin_memory()
        if not usage:
            return "unknown", None
        used, total = usage
        pct = used / total * 100.0
        text = "%s / %s  %s" % (human_bytes(used), human_bytes(total), meter(pct))
        return text, pct


    def get_root_disk():
        try:
            stats = os.statvfs("/")
            total = stats.f_blocks * stats.f_frsize
            available = stats.f_bavail * stats.f_frsize
            used = max(0, total - available)
            pct = used / total * 100.0
            text = "%s / %s  %s" % (human_bytes(used), human_bytes(total), meter(pct))
            return text, pct
        except Exception:
            return "unknown", None


    def get_generation():
        for path in ("/nix/var/nix/profiles/system", "/run/current-system"):
            if os.path.islink(path):
                try:
                    match = re.search(r"system-(\d+)-link", os.readlink(path))
                    if match:
                        return "#%s · system" % match.group(1)
                except Exception:
                    pass

        for path in (
            os.path.expanduser("~/.local/state/nix/profiles/home-manager"),
            os.path.expanduser("~/.nix-profile"),
        ):
            if os.path.islink(path):
                try:
                    match = re.search(r"home-manager-(\d+)-link", os.readlink(path))
                    if match:
                        return "#%s · home-manager" % match.group(1)
                except Exception:
                    pass
        return "unavailable"


    def refresh_nix_store(cache_path: str):
        if not os.path.exists("/nix/store"):
            return
        try:
            os.makedirs(os.path.dirname(cache_path), exist_ok=True)
            command_text = 'du -sh /nix/store 2>/dev/null | cut -f1 > "%s.tmp" && mv "%s.tmp" "%s"' % (
                cache_path,
                cache_path,
                cache_path,
            )
            subprocess.Popen(
                ["sh", "-c", command_text],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception:
            pass


    def get_nix_store():
        if not os.path.exists("/nix/store"):
            return "not mounted"
        try:
            if os.stat("/").st_dev != os.stat("/nix/store").st_dev:
                stats = os.statvfs("/nix/store")
                total = stats.f_blocks * stats.f_frsize
                used = max(0, total - stats.f_bavail * stats.f_frsize)
                return "%s / %s" % (human_bytes(used), human_bytes(total))

            cache_path = os.path.expanduser("~/.cache/nix-store-size")
            if os.path.exists(cache_path):
                if datetime.now().timestamp() - os.path.getmtime(cache_path) > 86400:
                    refresh_nix_store(cache_path)
                with open(cache_path, encoding="utf-8") as file:
                    size = file.read().strip()
                return "%s · shared with /" % size if size else "shared with /"

            refresh_nix_store(cache_path)
            return "shared with /"
        except Exception:
            return "unavailable"


    def get_ipv4():
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.settimeout(0.2)
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
        except Exception:
            return "offline"
        finally:
            sock.close()


    def get_tailscale_ipv4():
        output = command(["tailscale", "ip", "-4"], timeout=0.25)
        return output.split()[0] if output else paint("disconnected", DIM)


    def get_sessions():
        output = command(["who"], timeout=0.3)
        sessions = []
        for line in output.splitlines():
            parts = line.split()
            if len(parts) < 2:
                continue
            origin = parts[-1].strip("()") if len(parts) >= 5 and parts[-1].startswith("(") else ""
            sessions.append("%s@%s%s" % (parts[0], parts[1], " · " + origin if origin else ""))
        return ", ".join(sessions) if sessions else "none"


    def get_tmux_info():
        output = command(
            ["tmux", "list-sessions", "-F", "#{session_name}\t#{session_windows}\t#{?session_attached,attached,detached}"],
            timeout=0.3,
        )
        sessions = []
        for line in output.splitlines():
            parts = line.split("\t")
            if len(parts) != 3:
                continue
            name, windows, state = parts
            state_color = GREEN if state == "attached" else GRAY
            sessions.append("%s %sw %s" % (paint(name, BOLD), windows, paint(state, state_color)))
        return " · ".join(sessions) if sessions else paint("inactive", DIM)


    def get_zellij_info():
        output = command(["zellij", "list-sessions", "-n"], timeout=0.3)
        sessions = []
        for line in output.splitlines():
            line = line.strip()
            if not line or line.startswith("EXITED"):
                continue
            name = line.split()[0]
            if "(current)" in line:
                state = paint("current", GREEN)
            elif "(ATTACHED)" in line or "(attached)" in line:
                state = paint("attached", GREEN)
            else:
                state = paint("detached", GRAY)
            sessions.append("%s %s" % (paint(name, BOLD), state))
        return " · ".join(sessions) if sessions else paint("inactive", DIM)


    def get_herdr_info():
        output = command(["herdr", "workspace", "list"], timeout=0.3)
        try:
            workspaces = json.loads(output).get("result", {}).get("workspaces", [])
        except Exception:
            workspaces = []

        entries = []
        for workspace in workspaces:
            number = workspace.get("number", "?")
            label = workspace.get("label") or "workspace"
            tabs = workspace.get("tab_count", 0)
            panes = workspace.get("pane_count", 0)
            state = "focused" if workspace.get("focused") else workspace.get("agent_status", "idle")
            state_color = GREEN if workspace.get("focused") else GRAY
            entries.append(
                "%s %st %sp %s"
                % (
                    paint("%s:%s" % (number, label), BOLD),
                    tabs,
                    panes,
                    paint(state, state_color),
                )
            )
        return " · ".join(entries) if entries else paint("inactive", DIM)


    def card(title: str, rows, width: int):
        inner_width = width - 4
        title_text = "─ %s " % paint(title.upper(), BOLD, CYAN)
        top = paint("╭", GRAY) + title_text + paint("─" * max(0, width - 2 - visible_len(title_text)), GRAY) + paint("╮", GRAY)
        bottom = paint("╰" + "─" * (width - 2) + "╯", GRAY)
        label_width = min(11, max(len(label) for label, _ in rows))
        lines = [top]
        for label, value in rows:
            prefix = "%s %s" % (paint("◆", MAGENTA), paint(label.ljust(label_width), DIM))
            content = prefix + "  " + value
            lines.append(paint("│ ", GRAY) + fit(content, inner_width) + paint(" │", GRAY))
        lines.append(bottom)
        return lines


    def header(hostname: str, os_name: str, kernel: str, width: int):
        inner_width = width - 4
        title = paint("●", GREEN) + " " + paint(hostname.upper(), BOLD, CYAN)
        subtitle = paint(os_name, WHITE) + paint("  //  " + kernel, DIM)
        timestamp = datetime.now().astimezone().strftime("%A, %d %B · %H:%M %Z")
        eyebrow = paint(" NIX // SYSTEM STATUS ", BOLD, MAGENTA)
        top = paint("╭", GRAY) + eyebrow + paint("─" * max(0, width - 2 - visible_len(eyebrow)), GRAY) + paint("╮", GRAY)
        return [
            top,
            paint("│ ", GRAY) + fit(title, inner_width) + paint(" │", GRAY),
            paint("│ ", GRAY) + fit(subtitle, inner_width) + paint(" │", GRAY),
            paint("│ ", GRAY) + fit(paint(timestamp, DIM), inner_width) + paint(" │", GRAY),
            paint("╰" + "─" * (width - 2) + "╯", GRAY),
        ]


    def print_pair(left, right, gap=2):
        left_width = visible_len(left[0])
        height = max(len(left), len(right))
        left = left[:-1] + [""] * (height - len(left)) + left[-1:]
        right = right[:-1] + [""] * (height - len(right)) + right[-1:]
        for left_line, right_line in zip(left, right):
            print(fit(left_line, left_width) + " " * gap + right_line)


    def main():
        hostname, os_name, kernel = get_system()
        load, load_pct = get_load()
        memory, memory_pct = get_memory()
        root_disk, root_pct = get_root_disk()

        try:
            terminal_width = int(os.environ.get("MOTD_COLUMNS", ""))
        except ValueError:
            terminal_width = 0
        if terminal_width <= 0:
            terminal_width = shutil.get_terminal_size((92, 24)).columns
        width = max(24, min(terminal_width - 2, 108))
        wide = width >= 88

        overview = [
            ("Uptime", get_uptime()),
            ("Load", load),
            ("Logins", get_sessions()),
            ("Cores", str(os.cpu_count() or "unknown")),
        ]
        resources = [
            ("Memory", memory),
            ("Root", root_disk),
            ("Nix store", get_nix_store()),
            ("Generation", get_generation()),
        ]
        connectivity = [
            ("Local IPv4", get_ipv4()),
            ("Tailscale", get_tailscale_ipv4()),
        ]
        workspaces = [
            ("Herdr", get_herdr_info()),
            ("tmux", get_tmux_info()),
            ("zellij", get_zellij_info()),
        ]

        print()
        for line in header(hostname, os_name, kernel, width):
            print(line)
        print()

        if wide:
            card_width = min(44, (width - 2) // 2)
            print_pair(card("Overview", overview, card_width), card("Resources", resources, width - card_width - 2))
            print()
            print_pair(card("Connectivity", connectivity, card_width), card("Workspaces", workspaces, width - card_width - 2))
        else:
            sections = (
                card("Overview", overview, width),
                card("Resources", resources, width),
                card("Connectivity", connectivity, width),
                card("Workspaces", workspaces, width),
            )
            for index, section in enumerate(sections):
                if index:
                    print()
                for line in section:
                    print(line)

        pressures = [value for value in (load_pct, memory_pct, root_pct) if value is not None]
        peak = max(pressures, default=0.0)
        if peak >= 90:
            status = paint("● ATTENTION", RED, BOLD)
            message = paint("resource pressure is high", DIM)
        elif peak >= 75:
            status = paint("● WATCH", YELLOW, BOLD)
            message = paint("resource pressure is elevated", DIM)
        else:
            status = paint("● NOMINAL", GREEN, BOLD)
            message = paint("systems are operating normally", DIM)
        print("\n  %s  %s\n" % (status, message))


    if __name__ == "__main__":
        main()
  ''
