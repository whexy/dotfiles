---
name: spark
description: Search and read the user's email with the spark CLI (Spark Desktop) - list and filter emails, search by topic, read threads and attachments, and look up contact addresses. Use when the user asks about their email.
---

# Spark

`spark` is the CLI of the Spark email client. It is a thin client that talks
over IPC to the user's running Spark Desktop app and has no mailbox, network
stack, or credentials of its own. Run it directly on the user's computer,
never in a sandbox, container, or anything else cut off from their desktop
session. If Spark Desktop is not running, ask the user to launch it instead of
retrying.

Add `--json` to any command for the same data as JSON, with untruncated values,
snake_case keys, and ISO 8601 dates; a failure then prints
`{"error": {"message": "…"}}` and exits non-zero. Read the default text when
you only need to read the result, and use `--json` to process it, e.g.
`spark emails --json | jq '.emails[].id'`.

## Commands

| Command      | Use                                                    |
| ------------ | ------------------------------------------------------ |
| `accounts`   | List accounts and their access levels                  |
| `folders`    | List folders and labels with message counts            |
| `emails`     | Browse the Unified Inbox or one folder                 |
| `search`     | Search by topic with full bodies, or filter everywhere |
| `thread`     | Read a whole thread: headers, bodies, attachments      |
| `attachment` | Read one attachment by its ID                          |
| `contacts`   | Find a contact's address by name or domain             |

Run `spark accounts` first to see which accounts exist. Reading needs only the
read-only access level, set per account in Spark Desktop under Settings -> AI
Agents; a command the level does not allow fails with an error saying how to
change it.

Pick the command by the question:

- About content ("what did the landlord say about the deposit?"):
  `spark search "topic"`. It returns up to 20 emails with full bodies. Semantic
  matching and relevance ranking need Spark's AI Assistant (Settings -> Spark
  +AI); without it the match is keyword-only and unranked, so search for words
  the email would contain.
- By metadata across every folder ("every email from alice"):
  `spark search --filter "..."` with no topic. `emails` only sees the Unified
  Inbox or the one folder you name.
- Browsing the inbox or one folder: `spark emails`.

Both list commands show IDs and metadata only; `spark thread <ID>` reads the
full text.

## folders

```bash
spark folders                   # all accounts
spark folders user@example.com  # one account
```

The identifiers in parentheses are what `emails` and `search --in` accept.
Gmail-backed accounts show `(Gmail labels)` on their header.

| Format         | Example                    | Meaning                                      |
| -------------- | -------------------------- | -------------------------------------------- |
| Bare name      | `Inbox`, `Archive`         | Unified folder across accounts               |
| `email`        | `user@example.com`         | `emails`: that inbox; `search`: every folder |
| `email:Folder` | `user@example.com:Archive` | One account's folder or label                |

## emails

```bash
spark emails                                      # Unified Inbox
spark emails user@example.com:Archive             # one folder
spark emails --filter "from:alice@co.com is:unread"
spark emails --filter "newer_than:7d has:attachment"
spark emails --page 2 --page-size 20
spark emails --order ascending                    # oldest first
spark emails --new-senders                        # held back by GateKeeper
```

With GateKeeper in explicit mode, the Inbox hides mail from new senders and
shows how many there are at the top; `--new-senders` lists them.

Filters are Gmail-style and combine in one `--filter` string; `search` takes
the same operators.

| Operator                    | Values or example                                       |
| --------------------------- | ------------------------------------------------------- |
| `from:` `to:` `cc:`         | `from:alice@co.com`                                     |
| `subject:`                  | `subject:"quarterly report"`                            |
| `before:` `after:`          | `after:2026/01/01` (`yyyy/MM/dd`)                       |
| `newer_than:` `older_than:` | `newer_than:7d` (also `w`, `m`, `y`)                    |
| `has:`                      | `attachment`, `document`, `spreadsheet`, `presentation` |
| `is:`                       | `unread`, `read`, `starred`, `pinned`, `unreplied`      |
| `filename:`                 | `filename:report.pdf`                                   |
| `category:`                 | see below                                               |

Spark sorts incoming mail into categories: `priority`, `personal` (People,
person-to-person mail), `notification` (alerts, receipts), `newsletter`,
`invitation` (calendar invites), and `invitation_response` (RSVPs). For
example, `spark emails Inbox --filter "category:personal is:unread"`.

## search

```bash
spark search "quarterly report"
spark search "API integration" --filter "from:alice@co.com"
spark search "budget" --in user@example.com:Archive
spark search "vacation" --in user@example.com      # every folder of one account
spark search --filter "from:alice@co.com"          # no topic: list mode
spark search --filter "is:unread newer_than:7d" --page 2
```

Without `--in`, search covers every folder of every account. List mode pages
newest first (`--page`, `--page-size` default 50, `--order`) and leaves out
Trash, Spam, and Blocked unless `--in` names one of them.

## thread

```bash
spark thread 1114                                            # ID from emails or search
spark thread --download-attachments 1114                     # also fetch attachments
spark thread "https://sparkmailapp.com/dpl/bl?token=ABC..."  # Spark deep link
```

Prints every message in the thread with headers, full plain-text bodies, and
an `Attachments:` table, and lists the thread's custom labels once after the
summary line. The argument is an `ID:` from earlier output or a deep link from
a `Link:` line (`https://sparkmailapp.com/dpl/bl?token=...`,
`readdle-spark://bl=...`, or `readdlespark://bl=...`). A `Reply-To:` line
appears only when it differs from `From`; mailing lists and contact forms put
the real correspondent there.

The attachment table has `ID`, `Name`, `Size`, `MIME Type`, and `Path`;
`Path` reads `(not downloaded, ...)` until the file is fetched.

## attachment

```bash
spark attachment 42                        # metadata, one `Key: value` per line
spark attachment 42 --stream > report.pdf  # raw bytes on stdout
```

Takes an `ID` from a `thread` attachment table and downloads the file if it is
not cached yet. Use `--stream` when you can read the CLI's output but not the
local path it reports.

## contacts

```bash
spark contacts "john"         # strict match first, then fuzzy
spark contacts "example.com"
spark contacts --limit 100    # no query: most-used contacts (default 25, max 1000)
```

Use it to turn a name into an address for `from:` and `to:` filters.
