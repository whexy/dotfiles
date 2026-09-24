---
name: wechat
description: Message Wenxuan on WeChat with the `wechat` CLI - notify them when long work finishes or fails, send files or screenshots, or ask a question and wait for the reply from their phone. Use when they ask to be pinged, messaged, or reached on WeChat (微信).
---

# WeChat

`wechat` talks to Wenxuan's own WeChat through wechat-relay, a service on
their tailnet at https://wechat.at-basking.ts.net (override with
`WECHAT_RELAY_URL`). The relay holds the single bot login that every machine
and agent shares; no auth is needed. Every message goes to Wenxuan, and they
are the only person who talks to the bot. You cannot message their contacts or
groups.

Only use it when the user asked to be reached on WeChat for this task, or when
a standing instruction says to. These messages reach their phone, so keep them
rare and make each one worth reading.

## Before first use

```sh
wechat status          # exit 0: relay online; exit 1: not online or unreachable
wechat status --json   # state, window_open, window_remaining, queued, holding
```

If it is not online (`logged_out`, `logging_in`, `expired`, or unreachable),
stop and ask the user to open https://wechat.at-basking.ts.net and scan the QR
code with WeChat. You cannot do it for them.

## Sending

```sh
wechat send "Build finished: 42 tests passed"
some-command 2>&1 | tail -20 | wechat send      # stdin works too (or TEXT `-`)
wechat send "Screenshot of the bug" -f shot.png
wechat send -f report.pdf -f data.csv           # several attachments
```

- Images and videos show inline; everything else arrives as a file.
  `--as file` forces a file attachment.
- WeChat shows plain text. Markdown is not rendered, so drop headings and
  tables and keep it short. Lead with the outcome.
- Each text and each attachment is a separate message.

`send` exits 0 whether the message was delivered or queued; when queued it
prints `queued: <reason>` to stderr. Messages queue while another ask is
waiting for its reply, or when the 24h send window is closed (the bot can only
send within 24 hours of the user's last message to it). The relay reminds the
user before the window closes and delivers queued messages, marked delayed,
once they write again. So you never need to check the window before sending,
but if timely delivery matters, check `window_open` in `wechat status --json`.

## Asking and waiting

```sh
wechat ask "Deploy to prod now? Reply yes or no" --timeout 1800
wechat ask "Send a screenshot of the error" --download ./wx --json
```

`ask` sends the question and blocks until the user replies, then prints the
reply. This is the only way to get input from the user; there is no inbox.

The relay keeps the conversation strictly alternating. Once an ask is
delivered, it holds every later outgoing message, from any client, until the
user writes back, and that first message is the ask's reply. Messages the user
sends while no ask is waiting reach nobody. Only one ask is outstanding at a
time across all machines, so yours may wait behind another.

- `--timeout` defaults to 600s (max 86400) and counts from submission,
  including time spent queued. Set it generously, and run long waits in the
  background if your harness supports it.
- Exit code 3 means no reply before the timeout. Treat that as "no answer" and
  do not go ahead with anything risky. Exit 1 means the ask was cancelled from
  the relay web UI or failed to deliver. Ctrl-C cancels the ask.
- Ask one clear question and say what form of answer you expect ("Reply yes
  or no", "reply with a screenshot").
- Replies may carry images, files, video or voice notes; voice notes include
  WeChat's transcript in the text. With `--download DIR`, attachments are
  saved there and their paths printed; otherwise they are only listed.
- `--json` prints one object: `text`, `time`, optional `quote`, and
  `attachments` (each with `kind`, `name`, `size`, and optional `transcript`,
  `path`, `error`).

## Exit codes

`0` success (delivered or queued) · `1` error (message on stderr), relay not
online, or ask cancelled/failed · `3` no reply before timeout.
