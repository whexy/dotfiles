---
name: wechat
description: Message Wenxuan on WeChat with the `wechat` CLI - notify them when long work finishes or fails, send files or screenshots, ask a question and wait for the reply from their phone, or read what they sent. Use when they ask to be pinged, messaged, or reached on WeChat (微信), or ask you to check WeChat for instructions.
---

# WeChat

`wechat` talks to Wenxuan's own WeChat through a bot they bound by scanning a
QR code. By default every message goes to them, and they are the only person
who talks to the bot. You cannot message their contacts or groups.

Only use it when the user asked to be reached on WeChat for this task, or when
a standing instruction says to. These messages reach their phone, so keep them
rare and make each one worth reading.

## Before first use

```sh
wechat status          # exit 0: logged in; exit 1: not logged in
```

If it is not logged in, stop and ask the user to run `! wechat login`. Login
shows a QR code they must scan, and may ask for a number shown in WeChat, so
you cannot do it for them. `session expired` from any command means the same thing.

The bot can only send within 24 hours of the user's last message to it. Each
`recv` or `ask` that reads a message from the user resets that window.
`wechat status` shows how long is left (`send_window_seconds` with `--json`).
When the window is closed, `send` and `ask` fail before sending anything. In
that case, ask the user to message the bot from WeChat, then run `wechat recv`
and retry. If you will need to reach the user later, check the window before
starting long work, while they are still at the keyboard. If the work may
outlast the window, ask them to message the bot first.

## Sending

```sh
wechat send "Build finished: 42 tests passed"
some-command 2>&1 | tail -20 | wechat send      # stdin works too
wechat send "Screenshot of the bug" -f shot.png
wechat send -f report.pdf -f data.csv           # several attachments
```

- Images and videos show inline; everything else arrives as a file.
  `--as file` forces a file attachment.
- WeChat shows plain text. Markdown is not rendered, so drop headings and
  tables and keep it short. Lead with the outcome.
- Each text and each attachment is a separate message.

## Asking and waiting

```sh
wechat ask "Deploy to prod now? Reply yes or no" --timeout 1800
```

`ask` sends the question and blocks until the user replies, then prints the reply.
Only messages sent after the question count, so an old unread message is never
taken as the answer. Exit code 3 means no reply before the timeout. Treat that
as "no answer" and do not go ahead with anything risky. Run long waits in the
background if your harness supports it.

## Reading their messages

```sh
wechat recv                    # wait up to 5s; exit 3 when nothing new
wechat recv --wait 60 --json   # one JSON object per line
wechat recv --download ./wx    # also save images, files, voice and video
```

Each message has `from`, `time`, `text`, an optional `quote` (the message they
replied to), and `attachments`. Voice notes arrive as WeChat's transcript in
`text`. With `--download`, each attachment has a `path` you can open.

`recv` and `ask` use one shared inbox cursor: whatever one invocation reads,
no other invocation will see. Never run `wechat recv --follow` or `ask`
alongside another reader. Use exactly one reader at a time.

## Exit codes

`0` success · `1` error (message on stderr) · `3` nothing received / no reply
before timeout.
