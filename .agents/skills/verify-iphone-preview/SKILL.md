---
name: verify-iphone-preview
description: Model-check iPhone Use's live screen preview (the MCP app pua_ready and pua_screen show) against its rules around a password or Face ID pause, with the TLA+ model in checks/iphone-preview. Use when a change touches packages/iphone-use (its version, mjpeg-relay.patch, or the wrapper), packages/iphone-wda/iphone_use_select.py, or the iPhone module's wda ports, or when the preview behaves wrongly around a pause.
---

# Verify the iPhone preview

The live preview shows the phone's screen in the thread. Its frames come from
curl reading WebDriverAgent's MJPEG port (9100) through the loopback relay
that `iphone-use-select` starts, which `packages/iphone-use/mjpeg-relay.patch`
wires into iPhone Use's `ScreenHub`. Before the user enters a password or
uses Face ID, an agent pauses the preview.

`checks/iphone-preview/PreviewStream.tla` models one preview, the viewer, in
one iPhone Use process: the panel's `pua_screen_frame` polls, the stream
thread, curl and its connection, and a pause, user takeover and resume.

## The rules

| Rule                    | In plain words                                                                    | Harm if broken                                                            |
| ----------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `NeverShown`            | The panel never shows the phone while the user authenticates.                     | The password entry appears in the thread, where others viewing it see it. |
| `NeverKept`             | The viewer never keeps a frame of that screen as the frame a poll can return.     | A later poll, after the resume, can still show it.                        |
| `PauseErases`           | Once a pause made by the viewer's own process returns, the viewer holds no frame. | Pixels upstream promises to erase stay in memory.                         |
| `StalledStreamDropped`  | A connection that goes silent is dropped, so the stream reconnects.               | The panel freezes on a dead stream while it stays open.                   |
| `CaptureEndsWhenHidden` | Closing the panel ends curl.                                                      | The phone keeps streaming over the tailnet to nobody.                     |

## Run

```sh
nix build .#checks.x86_64-linux.iphone-preview -L
```

(`aarch64-darwin` on a Mac.) It runs TLC from the flake's nixpkgs on three
configs, one per pauser on this host, and must print "No error" for each:

- `Preview-reader.cfg`: the agent's `pua_screen(action=pause)`, on the
  viewer's request thread.
- `Preview-worker.cfg`: the pause a phone tool makes on a secure field, on the
  viewer's worker thread.
- `Preview-process.cfg`: another iPhone Use process on this host, through the
  shared `screen-state.json`.

`StallTimeout` is not taken from the configs: the check sets it from whether
the built `wda_screen.py` passes `--speed-limit` to curl. It also fails when
the server and `iphone_use_select.py` stop both naming
`IPHONE_USE_MJPEG_URL`.

To run one config by hand, or `Preview-host.cfg`, from the repo root:

```sh
nix shell --inputs-from . nixpkgs#tlaplus -c \
  tlc -workers auto -metadir "$(mktemp -d)" \
  -config checks/iphone-preview/Preview-host.cfg checks/iphone-preview/PreviewStream.tla
```

Read every result, passing or failing, with the `/statechart` skill: it gives
each broken rule's shortest path in plain words. The model has over 500
states, so `/statechart` charts only bug paths. Write its view module in a
scratch folder, labelling each step as the user sees it happen.

## Known finding: a pause on another host

`Preview-host.cfg` breaks `NeverKept` and `NeverShown`, and is left out of
the check on purpose. The pause lives in the pausing host's own
`~/.local/share/iphone-use/phones/<phone>/screen-state.json`, so a panel open
on another host keeps streaming:

1. On host B the panel is open and streaming.
2. An agent on host A pauses its preview before a password.
3. The user starts entering the password.
4. Host B's preview reads that frame, keeps it, and its panel shows it.

`replay.py` reproduced it on the real code with the live phone (step 3 of its
output). When a change shares the pause across hosts, move `host` into the
check's loop and delete this section.

## Is a failure a bug or the model?

1. Read the path with `/statechart`.
2. Replay it against the real code. `replay.py` runs the patched `ScreenHub`
   and the proxy's `Forward` against a phone, in temporary state directories:

   ```sh
   python3 -I .agents/skills/verify-iphone-preview/replay.py \
     "$(nix build .#iphone-use --no-link --print-out-paths)/share/iphone-use/server" \
     packages/iphone-wda/iphone_use_select.py iphone-17-pro.at-basking.ts.net 9100
   ```

   It needs the phone's WebDriverAgent running (`pua_phones` shows it
   answering). Extend it with the path's steps when the path is new.

3. If the real code does not do what the path says, assume the model is
   wrong until you show otherwise. Look first at the two places it
   simplifies:
   - **Atomic steps.** Each action is one section under `ScreenHub._lock`,
     one `screen-state.json` transaction, or one check in `_run`'s loops.
     `close()` is one step though it terminates curl after the lock.
   - **Timing.** `UserAuthenticates` assumes the user starts seconds after
     the pause returns, by which time `_run` has seen a pause written by
     another process: it checks the file at least every 0.1 s. Without it,
     TLC holds the stream thread still across the whole takeover. The
     viewer's own pauses need no such assumption, since `close()` sets
     `stop`.

Never weaken a rule or add an assumption to make a real path pass. Report it.

## What the model leaves out

- `pua_screen_action` refresh, which resumes even an authentication pause:
  the user's own click counts as the request to resume.
- Locked-phone pauses (`device_locked`), which follow the same file and
  `close()` path as `authentication`.
- Gestures, activity events, and the panel header's device label.
- More than one viewer process, or more than one frame in flight: the pipe
  holds at most one frame, and the connection goes silent at most once
  (`MaxStalls = 1`).
- The relay's own sockets: `Forward` is treated as part of curl's connection.

## Which code each part models

| Model                                          | Code                                                                                                             |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `PollReadsState`, `PollLeases`, `PollReturns`  | `ScreenHub.frame` and `_wire`, on `serve`'s request thread (`iphone_use.py`)                                     |
| `LeaseExpires`                                 | `FRAME_LEASE_SECONDS` in `frame`, read by `_live`                                                                |
| `CloseEffects`                                 | `ScreenHub.close`                                                                                                |
| `Live`                                         | `ScreenHub._live`                                                                                                |
| `StreamStarts` … `StreamBacksOff`              | `ScreenHub._run`, `_publish_frame`, `_terminate`                                                                 |
| `CurlGivesUp`, `StallTimeout`                  | `_command`'s curl flags, from `mjpeg-relay.patch`                                                                |
| `PauseWritten`, `PauseReturns`, `AgentResumes` | `ScreenHub.set_paused`; `_dispatch` for `pua_screen`, and the worker's pause on `phone_locked` or a secure field |
| `ReaderBusy`, `OwnPauser`                      | which thread `serve` runs a request on                                                                           |
| `IPHONE_USE_MJPEG_URL`                         | `Proxy.start_child` in `iphone_use_select.py`                                                                    |

When an intended change alters one of these, change the matching action in
the same change, rerun, and check that the model can still fail. Each of
these edits to a copy of the model must break its rule:

| Edit                                                                  | Config  | Breaks                              |
| --------------------------------------------------------------------- | ------- | ----------------------------------- |
| `StallTimeout = FALSE` (curl without `--speed-limit`)                 | worker  | `StalledStreamDropped`              |
| `StreamPublishes` ignores `stop` (`_publish_frame` without its check) | worker  | `PauseErases`                       |
| `OwnPauser == FALSE` (`set_paused` without `close()`)                 | reader  | `NeverKept`                         |
| `Live` without `~paused` (`_live` ignores the state file)             | process | `NeverKept`, and `NeverShown` alone |
| `Live` without `lease` (`_live` ignores the lease)                    | reader  | `CaptureEndsWhenHidden`             |

## Sync

Covered: `packages/iphone-use/default.nix` (iPhone Use 0.3.16, its patch and
wrapper), `packages/iphone-use/mjpeg-relay.patch`,
`packages/iphone-wda/iphone_use_select.py`, the `wda` ports in
`modules/home/agentic-tooling/iphone/default.nix`, and in upstream iPhone Use
`server/wda_screen.py` (`ScreenHub`) and `server/iphone_use.py` (`serve`,
`_dispatch`, the worker's automatic pause).

Last confirmed to describe the code at commit `40954a326968b86c867ee41affe531ae077cd484`.

To see what changed since:

```sh
git log --oneline 40954a326968b86c867ee41affe531ae077cd484..HEAD -- packages/iphone-use packages/iphone-wda/iphone_use_select.py \
  modules/home/agentic-tooling/iphone checks/iphone-preview
```

An iPhone Use version bump changes upstream code without touching our
files' logic: diff `ScreenHub` and `serve` between the two releases. Move the
sync commit forward only after you have confirmed that the model describes
the code at the new commit, and the check passes or fails only on the known
finding.
