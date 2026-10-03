---
name: web-preview
description: Running, checking, and showing web UIs and live previews on Wenxuan's machines - serving on the tailnet, driving a browser, taking and polishing screenshots, and handing him a URL he can open. Read before starting a server or preview (dev server, web UI, Typst/tinymist, an HTML artifact), verifying a UI change, capturing a screenshot, or giving him a link.
---

# Web Previews

You almost always run on a different machine from the one Wenxuan is sitting
at. Most of his hosts are headless NixOS servers (`mudd`, `neith`, `phobos`,
`deimos`, `zoozve`, `moore`, `wsl`): no display, no `xdg-open`, no browser on
`PATH`. A `localhost` URL is useless to him, and nothing can open a browser
for him.

Every host is on his tailnet (`at-basking.ts.net`), and so is every device he
browses from. So: **serve on the tailnet, verify it yourself, then hand him a
tailnet URL.** A tailnet URL also works when he is at the same machine, so
don't guess where he is.

## 1. Serve on the tailnet

1. Find this host's tailnet address:

   ```sh
   tailscale ip -4      # e.g. 100.122.135.13
   hostname             # MagicDNS name: <hostname>.at-basking.ts.net
   ```

2. Bind the server to that address (or `0.0.0.0`), not `127.0.0.1`, on a free
   high port (check with `ss -ltnp`). NixOS hosts trust `tailscale0`, so no
   firewall change is needed. Most tools take a host flag: `--host 0.0.0.0`,
   `--bind <ip>`, `HOST=0.0.0.0`.
3. Never open a browser: pass `--no-open` or equivalent.
4. Run it in the background and keep its PID.

**Hostname or IP.** Prefer `http://<hostname>.at-basking.ts.net:<port>`. Some
dev servers reject a `Host` header that does not match their bind address or
an allowlist; the page stays blank, returns 403, or its WebSocket fails:

- tinymist: use the IP; the MagicDNS name loads a blank page.
- Vite: add the name to `server.allowedHosts`, or use the IP.

When in doubt, use the IP URL. It always works.

**Typst preview:**

```sh
tinymist preview --no-open \
  --data-plane-host "$(tailscale ip -4):<port>" \
  --control-plane-host 127.0.0.1:0 \
  <file>.typ
```

`--control-plane-host 127.0.0.1:0` lets several previews run at once.

**HTTPS.** Plain HTTP is fine unless the page needs a secure context
(microphone, camera, clipboard, service workers, WebAuthn). Then use
Tailscale Serve, which the primary user may run without root:

```sh
tailscale serve status                                 # what is already served
tailscale serve --bg --https=<port> http://127.0.0.1:<port>
# -> https://<hostname>.at-basking.ts.net:<port>
```

Never touch an existing serve route, and never use port 443: on dev hosts it
serves T3 Code, the session you may be running in. Serve config persists
across restarts, so remove yours afterwards with
`tailscale serve --https=<port> off`.

Never expose a preview on a public host or tunnel.

## 2. Verify it yourself

Check from the tailnet address, not localhost:

```sh
curl -sS -o /dev/null -w '%{http_code}\n' "http://$(tailscale ip -4):<port>/"
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
- **Measure, don't eyeball.** For layout bugs, read sizes with
  `evaluate_script` (`getBoundingClientRect`, computed
  `grid-template-columns`) at the viewport where the bug shows.
- **Try the fix in the page first.** Inject a `<style>` with the candidate
  rule through `evaluate_script`, confirm it fixes the measurement, then edit
  the source.
- **Cover the states the change touches:** narrow and wide viewports, light
  and dark if the app has both, empty and long content.
- **Look at your own screenshot** (Read the PNG) before reporting. Report
  anything you could not check as unverified.

## 3. Publishable screenshots

For images that go into a README, docs, or anywhere public:

- Use real data from a real run, not mock data, unless he says otherwise.
- Capture at `deviceScaleFactor: 2`.
- No scrollbars or cut-off content in the frame. Size the viewport to the
  content, scroll inner panels to the meaningful part with `evaluate_script`,
  and hide scrollbars for the capture only
  (`* { scrollbar-width: none } ::-webkit-scrollbar { display: none }`).
- Crop to the subject; keep the app's own design.
- Compress losslessly with `oxipng`; `pngquant` leaves artifacts on
  transparent edges.
- Edit images with `nix run nixpkgs#imagemagick -- …` when Python imaging is
  not installed.
- Read every final image yourself before committing it.

## 4. Hand it over

Give him one line he can click, plus what to look at:

```
Preview: http://mudd.at-basking.ts.net:5173/runs/42 (the new summary bar is at the top)
```

Never give `localhost`, `127.0.0.1`, or LAN addresses. Say which process
serves it and leave it running until he is done.

## 5. Clean up

When he is done or the task ends, unless he asked to keep it: stop every
server and browser you started with `kill <PID>`, remove any serve route you
added, and delete scratch screenshots that aren't deliverables.
