---
name: test-ios-app
description: Check an iOS app on Wenxuan's Mac Mini simulators - when a simulator is worth it, where it runs, driving it through T3's device tools, the per-project harness and test account, and what a simulator cannot show. Use when a change to an iOS app (React Native, Expo or native) needs to be seen, tapped or screenshotted, when a review needs app screenshots, or when a project needs a simulator harness.
---

# Testing an iOS app

## Pick the layer

The project's automated checks prove most changes: the typecheck and the
unit tests, run in the Nix sandbox like every other test. Run them first,
and stop there unless:

- Wenxuan asked to see the change, or asked for screenshots;
- the change is about touch, scrolling, the keyboard, a system screen, or
  layout on a particular device size;
- a review needs screenshots of the app.

For those, use a simulator. A test that simulates touch handling is not
proof: a Jest test of responder negotiation once passed for a swipe fix that
did nothing on the phone. A gesture that drags a finger cannot be checked on
a simulator either ([below](#what-a-simulator-cannot-show)). Ask Wenxuan to
try it on the phone. Drive a real iPhone (`iphone-use`) only when Wenxuan
asks.

## Where it runs

The simulators, Xcode and the iOS builds are on the Mac Mini, `sheridan`.
Use the MacBook (`golf`) only when Wenxuan asks.

- Work in a checkout on the Mac: the clone at `~/Developer/<repo>`, or a
  worktree beside it at `~/Developer/<repo>-<name>`. Leave the clone's default
  branch alone for other sessions. You choose how your changes get there.
  The Mac's GitHub login can lapse; a push over ssh does not need it:
  `git push sheridan:Developer/<repo> <branch>`.
- From another host, run `ssh sheridan 'cd ~/Developer/<repo>-<name> && …'`.
  This is Tailscale SSH, which reports exit status 0 whatever the command
  did, so read the output.
- Put anything a script leaves on a Mac that can be rebuilt (builds, derived
  data, logs, copied checkouts) in `~/Library/Caches/<project>-<purpose>`.
  Never create a directory directly in the home.
- Keep at most two simulators booted on the Mac Mini, and boot them one at a
  time. Three, or two booting cold at once, overload it until even ssh hangs.

## Drive it through T3

T3's device tools show the simulator in Wenxuan's Device panel. Load them
with ToolSearch
`select:mcp__t3-code__device_list,mcp__t3-code__device_open,mcp__t3-code__device_screenshot,mcp__t3-code__device_close`,
call `device_list`, then `device_open` the simulator you were given, or a
free one. Never take a simulator another session holds. `device_open`
returns an `agent-device` command, called `$AD` below. Every launch, tap,
text entry, deep link and screenshot goes through it. Keep `simctl` for what
`$AD` cannot do: installing a build, writing the app's defaults or files
into its container, and `simctl addmedia`.

- `$AD snapshot -i` reads the screen as text, with refs to act on:
  `$AD press @e12`, `$AD fill @e5 "text"`. Take `$AD screenshot <path>` and
  read the PNG only to judge how something looks. Screenshots are 1x points
  by default; ask for `--pixel-density 3` only for review or reference sets.
- Send multi-step input as one `$AD batch`. Wait with `--settle`,
  `$AD wait text "…"` or `$AD wait stable`, never with `sleep`.
- Open a screen by deep link instead of tapping through tabs:
  `$AD open <bundle id> --launch-url <scheme>://<path>`. Opened as a launch
  URL, `agent-device` answers iOS's "Open in <app>?" prompt itself; a plain
  URL leaves the prompt up.
- Run `$AD` from outside the checkout. When a snapshot finds nothing it
  writes `snapshot-fallback.png` into the current directory.
- `$AD help <command>` lists a command's options.

When you finish, run the harness's `down`, then `device_close` with
`shutdown: true` for every simulator you opened.

## The project's harness

A project tested on simulators has one script for it and a project skill
that says how to use it. In SimpleStudio these are `mobile/scripts/sim.sh`
and `.agents/skills/ios-simulator`. Read both and use them. Do not set up a
bundler, a port, an install or a sign-in by hand. If the script cannot do
what you need, fix the script.

A project without one gets a script with these commands, and a project skill
for it:

| Command                    | Does                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `up`                       | starts this checkout's bundler (Metro) detached, on a port from the harness's own range, logging to the cache      |
| `build`                    | builds the Debug app once per native fingerprint, into a cache every checkout shares, one build at a time          |
| `attach <udid> ["$AD"]`    | installs the cached build if missing, points the app at this checkout's bundler, signs it in, opens it given `$AD` |
| `go "$AD" <path>`          | opens a screen by deep link                                                                                        |
| `tour "$AD" <dir> <label>` | screenshots every top-level screen, for reviews                                                                    |
| `status`                   | shows what runs for this checkout and whether the test session still holds                                         |
| `down`                     | stops this checkout's bundler and detaches its simulators                                                          |

- Key the build on the native side only: for Expo,
  `expo-updates runtimeversion:resolve` (or `@expo/fingerprint`). JavaScript
  edits then never rebuild. A cold build takes about 15 minutes, so run
  `build` in the background.
- A React Native Debug build reads its bundler address from the
  `RCT_jsLocation` default:
  `xcrun simctl spawn <udid> defaults write <bundle> RCT_jsLocation localhost:<port>`.
  That lets each simulator follow one checkout's bundler, with Fast Refresh,
  without Expo Go. Leave 8081, Metro's default, to the bundler that serves
  Wenxuan's phone.
- `go` and `tour` only run `$AD`, so they work from any host. The other
  commands run on the Mac.
- Print a failure as one line with a fixed prefix (`sim: …`), because ssh
  hides the exit status.
- After a change to `package.json` or the bundler's config, run `down`, `up`
  and `attach` again.

## The test account

Sign the app in as a test account kept for agents, never as Wenxuan.

- Its credentials are a 1Password item that the harness reads through
  `op-sa`. Never read, print or type them, and never sign in through the
  app's form. The harness mints a session, keeps it in the cache with mode
  600, and writes it into the app's container, where a Debug-only code path
  reads it.
- On production data, act as a careful user would, through the app or its
  API only. Never touch the database. Start slow or costly work (GPU jobs,
  messages to other people, anything paid) only when the change is about it,
  with the smallest settings, and never during a tour.
- Never change a product default to make a check easier. Adapt the check.
- Remove what your check created (uploads, records, ratings) unless Wenxuan
  asked to keep it. Fixtures that the project skill lists as the account's
  seed are not leftovers.
- A change that needs a server production does not run yet cannot be
  checked against production. Release the server first, or use the
  project's local server if it has one.

## What a simulator cannot show

- `agent-device` swipes and pans never reach a React Native
  `PanResponder`; taps do. Wenxuan checks gestures on the phone.
- There is no rotation. A wide device (an iPad, or an unfolded foldable) is
  the landscape check. A windowed iPad makes taps miss.
- `simctl io screenshot` captures a dark frame; use `$AD screenshot`.
- Some devices, such as the iPhone Duo, report accessibility frames that are
  off. Trust their screenshots.
- A development warning toast can cover the bottom of the screen:
  `$AD react-native dismiss-overlay`.

**The keyboard.** A focused field shows no software keyboard until you tap
it (`$AD press` on the field). `$AD type` sends hardware keystrokes and hides
the keyboard again. The next tap brings it back, so a tap aimed at a menu
row can land on a key instead. After typing, tap a neutral spot, take a
screenshot, then tap by coordinates. Tap Return and Backspace at their
coordinates from a fresh screenshot, because they move with the suggestion
bar. `fill <ref> ""` does not clear a field; hold Backspace with
`$AD press <x> <y> --count <n>`.

**System screens.** The photo picker, the Files picker and share sheets run
outside the app, so `snapshot -i` shows the app beneath them or nothing.
Drive them from a screenshot with `$AD press <x> <y>`, in points, which is
what a default 1x screenshot measures.

- `xcrun simctl addmedia <udid> <files>` on the Mac puts pictures and videos
  in the simulator's Photos.
- Nothing fills Files directly. Save an item there from Photos through `$AD`:
  `open com.apple.mobileslideshow`, open the item, then Share → Save to
  Files → On My iPhone → Save. Photos reports itself open before it is up,
  so take a screenshot before you read it.

## Reviews and delegates

Give each reviewer its own simulator (host id and device id from
`device_list`) and the Mac checkout whose bundler is up. Because at most two
simulators can be booted, run at most two reviewers at a time. The brief
needs one line, with no ssh or `simctl` steps for the device:

> Read the `test-ios-app` skill and `<project skill>`; `device_open` host
> `<hostId>` device `<id>`, then run `<harness> attach <id>` in
> `<checkout>` on the Mac Mini.
