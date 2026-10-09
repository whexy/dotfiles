---
name: web-preview
description: Serve a web UI to Wenxuan over the tailnet and hand him the URL. Use only when Wenxuan asks for a preview, a link, or a URL to open; not for checking your own UI work.
---

# Web Previews

You almost always run on a different machine from the one Wenxuan is sitting
at. Most of his hosts are headless NixOS servers (`mudd`, `neith`, `phobos`,
`deimos`, `zoozve`, `moore`, `wsl`): no display, no `xdg-open`, no browser on
`PATH`. A `localhost` URL is useless to him, and nothing can open a browser
for him.

Every host is on his tailnet (`at-basking.ts.net`), and so is every device he
browses from. So: **serve over Tailscale HTTPS, verify it yourself, then hand
him the `https://` tailnet URL.** That URL also works when he is at the same
machine, so don't guess where he is.

**Your browser is not his.** The firefox-devtools and Playwright browsers run
headless on this host. He cannot see them. Use them only to check pages
yourself. Never write that you opened, showed, or displayed a page for him, or
that it is "open in Firefox". A preview reaches him only as a link he opens.

## 1. Serve over Tailscale HTTPS

1. Start the server on `127.0.0.1` at a free high port (check with
   `ss -ltnp`). Never open a browser: pass `--no-open` or equivalent. Run it in
   the background and keep its PID.
2. Put Tailscale Serve in front of it. The primary user may run this without
   root:

   ```sh
   tailscale serve status                     # routes already in use
   tailscale serve --bg --https=<port> http://127.0.0.1:<port>
   # -> https://<hostname>.at-basking.ts.net:<port>
   ```

   The same number can be used for both ports; Serve listens on the tailnet
   address, the server on loopback.

Never use port 35338: on dev hosts it serves T3 Code, the session you may be
running in. Never touch an existing serve route. Serve config persists across
restarts, so remove yours afterwards with `tailscale serve --https=<port> off`.

The server receives `Host: <hostname>.at-basking.ts.net:<port>`. Dev servers
with a host allowlist reject it with a blank page or 403 until you allow it,
for example Vite's `server.allowedHosts`.

**Typst preview** is the one exception. tinymist drops every request whose
`Origin` is not its own bind address, so it fails behind Serve. Bind it to
the tailnet IP and hand over `http://<tailnet-ip>:<port>`:

```sh
tinymist preview --no-open \
  --data-plane-host "$(tailscale ip -4):<port>" \
  --control-plane-host 127.0.0.1:0 \
  <file>.typ
```

Use the IP, not the MagicDNS name. `--control-plane-host 127.0.0.1:0` lets
several previews run at once.

Never expose a preview on a public host or tunnel.

## 2. Verify it yourself

Check the URL you will hand over, not localhost:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' "https://$(hostname).at-basking.ts.net:<port>/"
```

A 200 is not enough when the page renders through JavaScript or a WebSocket:
load it in a browser.

### Pick the browser tool

| Need                                                        | Tool                                       |
| ----------------------------------------------------------- | ------------------------------------------ |
| Load a page, click, read the DOM, console, network          | firefox-devtools MCP tools (work headless) |
| Scripted or high-resolution captures, many states, cropping | Playwright with a Nix-built Chromium       |

The T3 Code `preview_*` tools need a desktop client to host them. On a
headless host `preview_open` fails with "No preview automation host is
available"; do not retry, use firefox-devtools.

**firefox-devtools:**

- If every call fails with "Process ... unexpectedly closed with status 0",
  call `restart_firefox` with `headless: true`, then retry.
- `screenshot_page` returns the image inline. To save a file, `saveTo` must
  be `true` (writes to `~/.firefox-devtools-mcp/output/`) or an absolute path
  inside `~/.firefox-devtools-mcp/`. Paths under `/tmp` or the repo are
  rejected.
- `take_snapshot` filters by relevance and can return an almost empty tree.
  Use `includeAll: true`, or read what you need with `evaluate_script`.
- Set the viewport with `set_viewport_size` before judging layout.

**Playwright:** do not run `npx playwright install`; its downloaded browsers
do not run on NixOS. Use Chromium from nixpkgs with `playwright-core`:

```sh
export CHROMIUM=$(nix build nixpkgs#chromium --no-link --print-out-paths)/bin/chromium
```

```js
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM });
const page = await browser.newPage({
  viewport: { width: 1440, height: 860 },
  deviceScaleFactor: 2,
});
```

Make locators specific (role or text plus context): a generic text locator
often matches several elements and fails strict mode.

### Check properly

- **Blank is not success.** Check console errors (`list_console_messages`
  with `level: "error"`) and failed requests (`list_network_requests`),
  especially WebSockets.
- **Cover the states the change touches:** narrow and wide viewports, light
  and dark if the app has both, empty and long content.
- **Look at your own screenshot** (Read the PNG) before reporting. Report
  anything you could not check as unverified.

## 3. Publishable screenshots

For images that go into a README, docs, or anywhere public, read
[screenshots.md](screenshots.md).

## 4. Hand it over

Give him one line he can click, plus what to look at:

```
Preview: https://mudd.at-basking.ts.net:5173/runs/42 (the new summary bar is at the top)
```

Never give `localhost`, `127.0.0.1`, or LAN addresses, and give `http://` only
for tinymist. Say which process serves it and leave it running until he is
done.

## 5. Clean up

When he is done or the task ends, unless he asked to keep it: stop every
server and browser you started with `kill <PID>`, remove any serve route you
added, and delete scratch screenshots that aren't deliverables.
