{ pkgs }:

pkgs.writers.writePython3Bin "motd"
  {
    flakeIgnore = [
      "E501" # long lines
      "W503" # line break before binary operator
    ];
  }
  ''
    """System Message of the Day (MOTD) banner.

    Displays a fast, beautifully formatted telemetry summary:
      - OS, Kernel, Uptime, Load, Sessions
      - Memory, Root disk, Nix store, Generation ID, IPv4, Tailscale IPv4
      - Multiplexers (tmux, zellij) active windows and session status
      - AI proxy quotas (Kimi, Codex, Antigravity) if available
    """

    import json
    import os
    import platform
    import re
    import shutil
    import socket
    import subprocess
    from datetime import datetime

    # --- ANSI Styling ---
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

    ANSI_RE = re.compile(r"\033\[[0-9;]*m")


    def visible_len(text: str) -> int:
        """Calculate printable length without ANSI escape codes."""
        return len(ANSI_RE.sub("", text))


    def paint(text: str, *codes) -> str:
        return "".join(codes) + str(text) + RESET


    def pad_lbl(lbl: str, width: int = 11) -> str:
        vlen = visible_len(lbl)
        return lbl + " " * max(0, width - vlen)


    def color_bar(pct: float, width: int = 10) -> str:
        pct = max(0.0, min(100.0, pct))
        filled = int(round(width * pct / 100.0))
        c = GREEN if pct < 60 else (YELLOW if pct < 85 else RED)
        bar_fill = "█" * filled
        bar_empty = "░" * (width - filled)
        return "%s%s%s%s%s%s %.0f%%" % (c, bar_fill, RESET, DIM, bar_empty, RESET, pct)


    # --- Telemetry Collectors ---


    def get_os_and_kernel():
        os_name = platform.system()
        if os.path.exists("/etc/os-release"):
            try:
                with open("/etc/os-release", encoding="utf-8") as f:
                    for line in f:
                        if line.startswith("PRETTY_NAME="):
                            os_name = line.split("=", 1)[1].strip().strip("\"'")
                            break
            except Exception:
                pass
        elif os_name == "Darwin":
            mac_ver = platform.mac_ver()[0]
            os_name = "macOS " + mac_ver if mac_ver else "macOS"

        kernel = "%s %s (%s)" % (platform.system(), platform.release(), platform.machine())
        hostname = socket.gethostname()
        return hostname, os_name, kernel


    def get_uptime():
        if os.path.exists("/proc/uptime"):
            try:
                with open("/proc/uptime", encoding="utf-8") as f:
                    secs = int(float(f.readline().split()[0]))
                    days, rem = divmod(secs, 86400)
                    hours, rem = divmod(rem, 3600)
                    mins = rem // 60
                    parts = []
                    if days:
                        parts.append("%dd" % days)
                    if hours:
                        parts.append("%dh" % hours)
                    parts.append("%dm" % mins)
                    return " ".join(parts)
            except Exception:
                pass
        try:
            res = subprocess.run(["uptime"], capture_output=True, text=True, timeout=0.3)
            if res.returncode == 0:
                m = re.search(r"up\s+(.*?),\s+\d+\s+user", res.stdout)
                if m:
                    return m.group(1).strip()
        except Exception:
            pass
        return "unknown"


    def get_load():
        try:
            l1, l5, l15 = os.getloadavg()
            return "%.2f, %.2f, %.2f" % (l1, l5, l15)
        except Exception:
            return "unknown"


    def get_memory():
        if os.path.exists("/proc/meminfo"):
            try:
                mem = {}
                with open("/proc/meminfo", encoding="utf-8") as f:
                    for line in f:
                        parts = line.split(":")
                        if len(parts) == 2:
                            mem[parts[0].strip()] = int(parts[1].split()[0])
                total_kb = mem.get("MemTotal", 0)
                avail_kb = mem.get("MemAvailable", mem.get("MemFree", 0) + mem.get("Buffers", 0) + mem.get("Cached", 0))
                used_kb = max(0, total_kb - avail_kb)
                if total_kb:
                    pct = (used_kb / total_kb) * 100
                    total_gb = total_kb / 1048576
                    used_gb = used_kb / 1048576
                    return "%.1fG / %.1fG  %s" % (used_gb, total_gb, color_bar(pct, 10))
            except Exception:
                pass
        return "unknown"


    def get_root_disk():
        try:
            st = os.statvfs("/")
            total = st.f_blocks * st.f_frsize
            free = st.f_bavail * st.f_frsize
            used = max(0, total - free)
            if total > 0:
                pct = (used / total) * 100
                total_gb = total / (1024**3)
                used_gb = used / (1024**3)
                return "%.0fG / %.0fG  %s" % (used_gb, total_gb, color_bar(pct, 10))
        except Exception:
            pass
        return "unknown"


    def get_generation():
        # Check system profile (NixOS / nix-darwin)
        for sys_path in ["/nix/var/nix/profiles/system", "/run/current-system"]:
            if os.path.islink(sys_path):
                try:
                    target = os.readlink(sys_path)
                    m = re.search(r"system-(\d+)-link", target)
                    if m:
                        return "#" + m.group(1) + " (system)"
                except Exception:
                    pass

        # Check Home Manager profile
        hm_paths = [
            os.path.expanduser("~/.local/state/nix/profiles/home-manager"),
            os.path.expanduser("~/.nix-profile"),
        ]
        for hm_path in hm_paths:
            if os.path.islink(hm_path):
                try:
                    target = os.readlink(hm_path)
                    m = re.search(r"home-manager-(\d+)-link", target)
                    if m:
                        return "#" + m.group(1) + " (home-manager)"
                except Exception:
                    pass
        return None


    def trigger_nix_store_bg_refresh(cache_path: str):
        """Trigger an asynchronous background computation of nix store size."""
        if not os.path.exists("/nix/store"):
            return
        cmd = 'du -sh /nix/store 2>/dev/null | cut -f1 > "%s.tmp" && mv "%s.tmp" "%s"' % (
            cache_path,
            cache_path,
            cache_path,
        )
        try:
            subprocess.Popen(
                ["sh", "-c", cmd],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception:
            pass


    def get_nix_store():
        if not os.path.exists("/nix/store"):
            return None
        try:
            st_root = os.stat("/")
            st_nix = os.stat("/nix/store")
            if st_root.st_dev != st_nix.st_dev:
                nst = os.statvfs("/nix/store")
                total = nst.f_blocks * nst.f_frsize
                free = nst.f_bavail * nst.f_frsize
                used = max(0, total - free)
                if total > 0:
                    pct = (used / total) * 100
                    return "%.1fG / %.1fG (%.0f%%)" % (used / (1024**3), total / (1024**3), pct)
            else:
                # Same mount as root; check cache file if available
                cache_file = os.path.expanduser("~/.cache/nix-store-size")
                if os.path.exists(cache_file):
                    try:
                        mtime = os.path.getmtime(cache_file)
                        # Refresh cache if older than 24 hours
                        if datetime.now().timestamp() - mtime > 86400:
                            trigger_nix_store_bg_refresh(cache_file)

                        with open(cache_file, encoding="utf-8") as f:
                            size = f.read().strip()
                            if size:
                                return size + " (on /)"
                    except Exception:
                        pass
                else:
                    trigger_nix_store_bg_refresh(cache_file)
                return "shared with /"
        except Exception:
            return None


    def get_ipv4():
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return "unknown"


    def get_tailscale_ipv4():
        try:
            res = subprocess.run(
                ["tailscale", "ip", "-4"],
                capture_output=True,
                text=True,
                timeout=0.25,
            )
            if res.returncode == 0:
                out = res.stdout.strip().split()
                if out:
                    return out[0]
        except Exception:
            pass
        return None


    def get_sessions():
        sessions = []
        try:
            res = subprocess.run(["who"], capture_output=True, text=True, timeout=0.3)
            if res.returncode == 0:
                for line in res.stdout.strip().splitlines():
                    parts = line.split()
                    if len(parts) >= 2:
                        user, tty = parts[0], parts[1]
                        ip = parts[-1].strip("()") if len(parts) >= 5 and parts[-1].startswith("(") else ""
                        ip_text = " from " + ip if ip else ""
                        sessions.append("%s (%s%s)" % (user, tty, ip_text))
        except Exception:
            pass
        return sessions


    def get_tmux_info():
        sessions = []
        try:
            res = subprocess.run(
                ["tmux", "list-sessions", "-F", "#{session_name}\t#{session_windows}\t#{?session_attached,attached,detached}"],
                capture_output=True,
                text=True,
                timeout=0.3,
            )
            if res.returncode == 0:
                for line in res.stdout.strip().splitlines():
                    if not line:
                        continue
                    parts = line.split("\t")
                    if len(parts) < 3:
                        continue
                    sname, swins, satt = parts[0], parts[1], parts[2]
                    # List windows for session
                    w_res = subprocess.run(
                        ["tmux", "list-windows", "-t", sname, "-F", "#{window_index}:#{window_name}#{?window_active,*,}"],
                        capture_output=True,
                        text=True,
                        timeout=0.2,
                    )
                    if w_res.returncode == 0 and w_res.stdout.strip():
                        win_str = " ".join(w_res.stdout.strip().splitlines())
                    else:
                        win_str = "%s windows" % swins
                    att_color = GREEN if satt == "attached" else DIM
                    att_str = paint("(%s)" % satt, att_color)
                    sessions.append("%s [%s] %s" % (paint(sname, BOLD), win_str, att_str))
        except Exception:
            pass
        return sessions


    def get_zellij_info():
        sessions = []
        try:
            res = subprocess.run(
                ["zellij", "list-sessions", "-n"],
                capture_output=True,
                text=True,
                timeout=0.3,
            )
            if res.returncode == 0:
                for line in res.stdout.strip().splitlines():
                    line = line.strip()
                    if not line or line.startswith("EXITED"):
                        continue
                    sname = line.split()[0]
                    if "(current)" in line:
                        status = paint("(current)", GREEN)
                    elif "(ATTACHED)" in line or "(attached)" in line:
                        status = paint("(attached)", GREEN)
                    else:
                        status = paint("(detached)", DIM)
                    sessions.append("%s %s" % (paint(sname, BOLD), status))
        except Exception:
            pass
        return sessions


    def trigger_ai_quota_bg_refresh(cache_path: str):
        """Trigger a background refresh of the AI quota cache if executable exists."""
        ai_quota_bin = shutil.which("ai-quota")
        if not ai_quota_bin:
            return
        cmd = '"%s" --json > "%s.tmp" 2>/dev/null && mv "%s.tmp" "%s"' % (
            ai_quota_bin,
            cache_path,
            cache_path,
            cache_path,
        )
        try:
            subprocess.Popen(
                ["sh", "-c", cmd],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception:
            pass


    def get_ai_quota():
        cache_path = os.path.expanduser("~/.cache/ai-quota.json")
        data = None

        # Check if cache exists
        if os.path.exists(cache_path):
            try:
                # If cache is older than 10 minutes, trigger background refresh
                mtime = os.path.getmtime(cache_path)
                if datetime.now().timestamp() - mtime > 600:
                    trigger_ai_quota_bg_refresh(cache_path)

                with open(cache_path, encoding="utf-8") as f:
                    data = json.load(f)
            except Exception:
                data = None
        else:
            # Trigger background fetch for future shells
            trigger_ai_quota_bg_refresh(cache_path)

        if not data or not data.get("providers"):
            return []

        rows = []
        for p in data.get("providers", []):
            pname = p.get("provider")
            accounts = p.get("accounts", [])
            for acct in accounts:
                if acct.get("error"):
                    continue
                meters = acct.get("meters", [])
                if not meters:
                    continue

                meter_strs = []
                for m in meters:
                    lbl = m.get("label", "")
                    pct = float(m.get("pct", 0.0))
                    # Shorten labels for clean display
                    lbl_clean = lbl.replace("-minute", "m").replace("-hour", "h").replace("-week", "w")
                    meter_strs.append("%s %s" % (lbl_clean, color_bar(pct, 8)))

                notes = acct.get("notes", [])
                note_str = ""
                if notes:
                    note_str = " " + paint("(" + notes[0][1] + ")", DIM)
                elif acct.get("subtitle") and "plus" in acct.get("subtitle", ""):
                    note_str = " " + paint("(plus)", DIM)

                rows.append((pname, " · ".join(meter_strs) + note_str))
        return rows


    # --- Main Formatter & Display ---


    def main():
        hostname, os_name, kernel = get_os_and_kernel()
        uptime = get_uptime()
        load = get_load()
        memory = get_memory()
        root_disk = get_root_disk()
        gen_id = get_generation()
        nix_store = get_nix_store()
        ipv4 = get_ipv4()
        ts_ipv4 = get_tailscale_ipv4()
        sessions = get_sessions()
        tmux_info = get_tmux_info()
        zellij_info = get_zellij_info()
        ai_quota = get_ai_quota()

        term_width = shutil.get_terminal_size((80, 24)).columns
        rule_width = min(term_width - 2, 78)

        # 1. Header
        header = " %s %s %s %s %s" % (
            paint(hostname, BOLD, CYAN),
            paint("·", DIM),
            paint(os_name, WHITE),
            paint("·", DIM),
            paint(kernel, DIM),
        )
        print()
        print(header)
        print(" %s" % paint("─" * rule_width, DIM))

        # 2. System & Resources Table
        gen_text = ("Gen " + gen_id) if gen_id else "N/A"
        store_text = ("%s · %s" % (nix_store, gen_text)) if nix_store else gen_text

        col1 = [
            (pad_lbl(paint("Uptime:", DIM), 11), uptime),
            (pad_lbl(paint("Load:", DIM), 11), load),
            (pad_lbl(paint("Sessions:", DIM), 11), ", ".join(sessions) if sessions else "none"),
            (pad_lbl(paint("IPv4:", DIM), 11), ipv4),
        ]

        col2 = [
            (pad_lbl(paint("Memory:", DIM), 11), memory),
            (pad_lbl(paint("Root (/):", DIM), 11), root_disk),
            (pad_lbl(paint("Nix Store:", DIM), 11), store_text),
            (pad_lbl(paint("Tailscale:", DIM), 11), ts_ipv4 if ts_ipv4 else paint("disconnected", DIM)),
        ]

        col1_w = max(visible_len(lbl) + visible_len(val) for lbl, val in col1)
        col1_w = max(col1_w, 32)

        # If terminal is very narrow (<70 cols), render stacked columns
        if term_width < 70:
            print(" %s" % paint("● System", BOLD, CYAN))
            for lbl, val in col1:
                print("   %s%s" % (lbl, val))
            print("\n %s" % paint("● Resources & Storage", BOLD, CYAN))
            for lbl, val in col2:
                print("   %s%s" % (lbl, val))
        else:
            title1 = paint("● System", BOLD, CYAN)
            title2 = paint("● Resources & Storage", BOLD, CYAN)
            pad_title = (col1_w + 3) - visible_len(title1) + 1
            print(" %s%s%s" % (title1, " " * max(1, pad_title), title2))

            for (lbl1, val1), (lbl2, val2) in zip(col1, col2):
                pad1 = col1_w - (visible_len(lbl1) + visible_len(val1))
                line = "   %s%s%s   %s%s" % (lbl1, val1, " " * max(0, pad1), lbl2, val2)
                print(line)

        # 3. Multiplexers Section
        print("\n %s" % paint("● Multiplexers", BOLD, CYAN))
        tmux_str = ", ".join(tmux_info) if tmux_info else paint("inactive", DIM)
        zellij_str = ", ".join(zellij_info) if zellij_info else paint("inactive", DIM)
        print("   %s %s" % (pad_lbl(paint("tmux:", DIM), 10), tmux_str))
        print("   %s %s" % (pad_lbl(paint("zellij:", DIM), 10), zellij_str))

        # 4. AI Quota Section (if present)
        if ai_quota:
            print("\n %s" % paint("● AI Quota", BOLD, CYAN))
            for pname, qstr in ai_quota:
                print("   %s %s" % (pad_lbl(paint(pname + ":", DIM), 14), qstr))

        print()


    if __name__ == "__main__":
        main()
  ''
