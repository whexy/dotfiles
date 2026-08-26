{ pkgs }:

# Fetch quota for direct subscriptions and accounts on the tailnet AI proxy.
#
# Proxy providers use CLIProxyAPI's management /api-call endpoint. Direct
# providers authenticate from their own agenix-provisioned key files.
pkgs.writers.writePython3Bin "ai-quota"
  {
    flakeIgnore = [
      "E501" # long lines (endpoint URLs)
      "W503" # line break before binary operator
    ];
  }
  ''
    """Fetch quota for configured AI accounts.

    Pass --json for machine-readable output (consumed by the bar pills).
    """

    import json
    import os
    import sys
    import urllib.error
    import urllib.request
    from concurrent.futures import ThreadPoolExecutor
    from datetime import datetime, timezone

    API_BASE = "https://ai-proxy.at-basking.ts.net"
    MGMT = API_BASE + "/v0/management"
    KEY_FILE = os.path.expanduser("~/.secrets/ai-proxy-mgmt-key")
    OPENCODE_KEY_FILE = os.path.expanduser("~/.secrets/opencode-api-key")

    BAR_WIDTH = 20

    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    CYAN = "\033[36m"
    MAGENTA = "\033[35m"


    def paint(text, *codes):
        return "".join(codes) + str(text) + RESET


    def to_int(value):
        try:
            return int(value)
        except (TypeError, ValueError):
            return None


    def parse_time(value):
        if not value:
            return None
        try:
            return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        except ValueError:
            return None


    def parse_epoch(value):
        ts = to_int(value)
        if ts is None:
            return None
        return datetime.fromtimestamp(ts, timezone.utc)


    def seconds_until(dt):
        if dt is None:
            return None
        return int((dt - datetime.now(timezone.utc)).total_seconds())


    def human_delta(seconds):
        if seconds is None:
            return None
        if seconds <= 0:
            return "now"
        minutes = seconds // 60
        days, minutes = divmod(minutes, 60 * 24)
        hours, minutes = divmod(minutes, 60)
        if days:
            return "%dd %dh" % (days, hours)
        if hours:
            return "%dh %dm" % (hours, minutes)
        return "%dm" % minutes


    def usage_color(pct):
        if pct >= 80:
            return RED
        if pct >= 50:
            return YELLOW
        return GREEN


    def window_label(seconds):
        seconds = to_int(seconds)
        if not seconds:
            return "window"
        for unit, size in (("week", 604800), ("day", 86400), ("hour", 3600), ("min", 60)):
            if seconds >= size and seconds % size == 0:
                n = seconds // size
                if (unit, n) == ("week", 1):
                    return "weekly"
                if (unit, n) == ("day", 1):
                    return "daily"
                return "%d-%s" % (n, unit)
        return "%ds" % seconds


    def meter(label, detail):
        used = to_int(detail.get("used"))
        limit = to_int(detail.get("limit"))
        remaining = to_int(detail.get("remaining"))
        if remaining is None and used is not None and limit is not None:
            remaining = limit - used
        pct = used / limit * 100 if used is not None and limit else 0.0
        return {
            "label": label,
            "pct": pct,
            "reset": parse_time(detail.get("resetTime")),
        }


    def parse_kimi(body):
        user = body.get("user", {})
        membership = user.get("membership", {})
        region = str(user.get("region", "?")).replace("REGION_", "").lower()
        level = str(membership.get("level", "?")).replace("LEVEL_", "").lower()
        subtitle = "%s (%s, %s)" % (user.get("userId", "?"), region, level)

        meters = [meter("weekly", body.get("usage", {}))]
        for w in body.get("limits", []):
            win, det = w.get("window", {}), w.get("detail", {})
            unit = str(win.get("timeUnit", "")).replace("TIME_UNIT_", "").lower()
            meters.append(meter("%s-%s" % (win.get("duration", "?"), unit), det))

        notes = []
        parallel = body.get("parallel", {})
        if parallel:
            notes.append(("parallel", "%s concurrent" % parallel.get("limit", "?")))
        return subtitle, meters, notes


    def parse_codex(body):
        subtitle = "%s (%s)" % (body.get("email", "?"), body.get("plan_type", "?"))

        meters = []
        for rl_key, prefix in (("rate_limit", ""), ("code_review_rate_limit", "review ")):
            rl = body.get(rl_key) or {}
            for win in (rl.get("primary_window"), rl.get("secondary_window")):
                if not win:
                    continue
                meters.append(
                    {
                        "label": prefix + window_label(win.get("limit_window_seconds")),
                        "pct": float(win.get("used_percent") or 0),
                        "reset": parse_epoch(win.get("reset_at")),
                    }
                )

        notes = []
        credits = body.get("credits") or {}
        if credits.get("has_credits"):
            notes.append(("credits", "balance %s" % credits.get("balance", "?")))
        return subtitle, meters, notes


    def parse_opencode_go(body):
        meters = []
        for label, usage in (body.get("usage") or {}).items():
            if not isinstance(usage, dict):
                continue
            meters.append(
                {
                    "label": "5-hour" if label == "rolling" else label,
                    "pct": float(usage.get("percent") or 0),
                    "reset": parse_time(usage.get("resetsAt")),
                }
            )
        return None, meters, []


    def parse_antigravity(body):
        # Buckets share quota pools; group models with identical usage and
        # reset time into one meter instead of listing every model.
        groups = {}
        for b in body.get("buckets", []):
            model = b.get("modelId")
            if not model or model.startswith(("chat_", "tab_")):
                continue  # internal models, not user-facing quota
            frac = b.get("remainingFraction")
            pct = (1 - float(frac)) * 100 if frac is not None else 0.0
            reset = parse_time(b.get("resetTime"))
            groups.setdefault((round(pct, 4), reset), []).append(model)

        meters = []
        for (pct, reset), models in groups.items():
            prefix = os.path.commonprefix(models)
            if len(models) > 1 and prefix:
                label = "%s* (%d)" % (prefix, len(models))
            elif len(models) > 1:
                label = "%s +%d" % (models[0], len(models) - 1)
            else:
                label = models[0]
            meters.append({"label": label, "pct": pct, "reset": reset})
        meters.sort(key=lambda m: -m["pct"])
        return None, meters, []


    PROVIDERS = {
        "kimi": {
            "request": {
                "method": "GET",
                "url": "https://api.kimi.com/coding/v1/usages",
                "header": {"Authorization": "Bearer $TOKEN$"},
            },
            "parse": parse_kimi,
        },
        "codex": {
            "request": {
                "method": "GET",
                "url": "https://chatgpt.com/backend-api/wham/usage",
                "header": {"Authorization": "Bearer $TOKEN$"},
            },
            "parse": parse_codex,
        },
        "antigravity": {
            "request": {
                "method": "POST",
                # The quota endpoint 403s (a misleading "no valid license"
                # error) unless the request carries an Antigravity
                # User-Agent. The daily (staging) endpoint works the same
                # way; fall back to production on 403/404.
                "url": "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
                "url_fallbacks": [
                    "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
                ],
                "header": {
                    "Authorization": "Bearer $TOKEN$",
                    "Content-Type": "application/json",
                    "User-Agent": "antigravity/hub/1.15.8 darwin/arm64",
                },
                "body": "{}",
            },
            "parse": parse_antigravity,
        },
    }


    def load_key(env_name, file_env_name, default_file):
        key = os.environ.get(env_name)
        if key:
            return key
        key_file = os.environ.get(file_env_name, default_file)
        try:
            with open(key_file, encoding="utf-8") as f:
                return f.read().strip()
        except OSError:
            return None


    def direct_api(url, key, timeout=30):
        req = urllib.request.Request(
            url,
            headers={
                "Authorization": "Bearer " + key,
                "User-Agent": "opencode/ai-quota",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return {"status_code": resp.status, "body": resp.read().decode()}
        except urllib.error.HTTPError as exc:
            return {"status_code": exc.code, "body": exc.read().decode()}


    def api(key, path, payload=None, timeout=30):
        data = json.dumps(payload).encode() if payload is not None else None
        req = urllib.request.Request(
            MGMT + path,
            data=data,
            headers={
                "Authorization": "Bearer " + key,
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.load(resp)


    def finalize_meters(meters):
        for m in meters:
            dt = m.get("reset")
            secs = seconds_until(dt)
            m["reset"] = dt.astimezone(timezone.utc).isoformat() if dt else None
            m["reset_in"] = secs
            m["reset_human"] = human_delta(secs)
            m["reset_local"] = (
                dt.astimezone().strftime("%b %d %H:%M") if dt else None
            )
        return meters


    def build_account(name, resp, parse):
        status = resp.get("status_code", 0)
        if status != 200:
            return {
                "name": name,
                "subtitle": None,
                "error": "HTTP %d: %s" % (status, str(resp.get("body", ""))[:200]),
                "meters": [],
                "notes": [],
            }
        subtitle, meters, notes = parse(json.loads(resp.get("body") or "{}"))
        return {
            "name": name,
            "subtitle": subtitle,
            "error": None,
            "meters": finalize_meters(meters),
            "notes": notes,
        }


    def quota_line(m):
        pct = min(max(m["pct"], 0.0), 100.0)
        filled = round(BAR_WIDTH * pct / 100.0)
        graph = paint("█" * filled, usage_color(pct)) + paint(
            "░" * (BAR_WIDTH - filled), DIM
        )
        note = ""
        if m["reset_human"]:
            note = paint(
                " · resets in %s (%s)" % (m["reset_human"], m["reset_local"]),
                DIM,
            )
        return "%s %.0f%% used%s" % (graph, pct, note)


    def print_account(acct):
        rows = []
        if acct["error"]:
            rows.append(paint("error: %s" % acct["error"], RED))
        else:
            labels = (
                (["user"] if acct["subtitle"] else [])
                + [m["label"] for m in acct["meters"]]
                + [label for label, _ in acct["notes"]]
            )
            width = max([len(lbl) for lbl in labels] or [0])
            if acct["subtitle"]:
                rows.append(paint("user".ljust(width), DIM) + " " + acct["subtitle"])
            for m in acct["meters"]:
                rows.append(paint(m["label"].ljust(width), DIM) + " " + quota_line(m))
            for label, text in acct["notes"]:
                rows.append(paint(label.ljust(width), DIM) + " " + text)
        print("  " + paint("● ", CYAN) + paint(acct["name"], BOLD))
        for r in rows:
            print("    " + r)


    def fetch_proxy_account(key, spec, f):
        urls = [spec["request"]["url"]] + spec["request"].get(
            "url_fallbacks", []
        )
        resp = {}
        for url in urls:
            request = dict(spec["request"], url=url)
            request.pop("url_fallbacks", None)
            try:
                resp = api(
                    key,
                    "/api-call",
                    payload=dict(request, authIndex=f["auth_index"]),
                )
            except OSError as exc:
                resp = {"status_code": 0, "body": str(exc)}
            if resp.get("status_code") not in (403, 404):
                break
        return build_account(f["name"], resp, spec["parse"])


    def fetch_proxy_providers(key, pool):
        if not key:
            return []
        files = api(key, "/auth-files", timeout=20).get("files", [])
        tasks = [
            (f.get("provider"), f)
            for f in files
            if f.get("provider") in PROVIDERS and not f.get("disabled")
        ]
        # One fan-out across all accounts; pool.map preserves auth-file order.
        results = pool.map(
            lambda t: fetch_proxy_account(key, PROVIDERS[t[0]], t[1]), tasks
        )
        accounts = {}
        for (provider, _), acct in zip(tasks, results):
            accounts.setdefault(provider, []).append(acct)
        return [
            {"provider": provider, "accounts": accounts[provider]}
            for provider in PROVIDERS
            if provider in accounts
        ]


    def fetch_opencode_go(key):
        if not key:
            return None
        try:
            resp = direct_api("https://opencode.ai/zen/go/v1/usage", key)
        except OSError as exc:
            resp = {"status_code": 0, "body": str(exc)}
        return {
            "provider": "opencode-go",
            "accounts": [build_account("OpenCode Go", resp, parse_opencode_go)],
        }


    def main():
        mgmt_key = load_key("MGMT_KEY", "MGMT_KEY_FILE", KEY_FILE)
        opencode_key = load_key(
            "OPENCODE_API_KEY", "OPENCODE_API_KEY_FILE", OPENCODE_KEY_FILE
        )
        # All fetches are blocking HTTP I/O, so threads overlap them: the
        # OpenCode Go call runs while the proxy account calls fan out.
        with ThreadPoolExecutor(max_workers=8) as pool:
            opencode_future = pool.submit(fetch_opencode_go, opencode_key)
            try:
                providers = fetch_proxy_providers(mgmt_key, pool)
            except OSError as exc:
                sys.exit("error: failed to list proxy auth files: %s" % exc)
            opencode = opencode_future.result()
        if opencode:
            providers.append(opencode)
        if not providers:
            sys.exit("No configured accounts with a known quota endpoint found.")

        if "--json" in sys.argv[1:]:
            print(json.dumps({"providers": providers}))
            return

        first = True
        for entry in providers:
            if not first:
                print()
            first = False
            print(paint(entry["provider"], BOLD, MAGENTA))
            for acct in entry["accounts"]:
                print_account(acct)


    if __name__ == "__main__":
        main()
  ''
