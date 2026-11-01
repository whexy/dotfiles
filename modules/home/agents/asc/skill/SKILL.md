---
name: asc
description: Work with App Store Connect through the asc CLI - apps, builds, TestFlight, submissions and review, metadata, screenshots, signing, pricing, analytics, and the raw API. Use when a task touches App Store Connect, TestFlight, or an App Store release.
---

# asc

`asc` is the App Store Connect CLI. This skill only says where its guidance
lives: the CLI documents itself, and that output matches the installed
version, so read it instead of relying on memory.

## Finding the right command

| Need                                       | Run                                     |
| ------------------------------------------ | --------------------------------------- |
| Which command does a task                  | `asc search "<task>" --output markdown` |
| A command's flags and examples             | `asc <command> [<subcommand>] --help`   |
| Recipes for release, TestFlight, and Xcode | `asc docs show workflows`               |
| API quirks (dates, finance, sandbox)       | `asc docs show api-notes`               |
| A quick reference of common commands       | `asc docs show reference`               |
| Whether the public API covers a workflow   | `asc capabilities --output markdown`    |
| Field names and allowed values of an API   | `asc schema <resource or METHOD /path>` |

`asc docs list` names every embedded guide. Read the guide for the workflow
at hand before running its commands; they change between releases.

Do not run `asc install-skills`, `asc init`, or `asc docs init`: they write
skill packs or an `ASC.md` outside what the user asked for.

## Authentication

`asc` loads the user's API key from 1Password on each run, so never run
`asc auth login`.
If a command reports missing authentication, run `asc auth status --validate`
and tell the user what it says; do not create or store other credentials.

## Changing App Store Connect

Commands act on the user's live apps. Explore with `asc --read-only
<command>` (or `ASC_READ_ONLY=1`), which refuses every mutating request
before it is sent. Before a command that
uploads, submits, edits, or deletes, run its `--dry-run` when it has one, show
the user the plan, and wait for their go-ahead; then pass `--confirm` where
the command asks for it.

## Output

Output is JSON when stdout is not a terminal. Pass `--output json` (or
`table`, `markdown`) explicitly in commands you show the user or put in
scripts, and `--paginate` when a list must be complete.
