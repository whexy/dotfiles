# Auto-upgrade daemon

`dotfiles-upgraded` keeps one host converged on the upstream dotfiles
repository. CI announces each commit that passes on master, and the daemon
switches to it as soon as the announcement arrives; it also polls
`refs/heads/master` over HTTPS, waits for that commit's CI verdict, and runs the
platform's rebuild command. It never accepts an inbound connection, so it
reaches NAT'd laptops, Cloudflare-only hosts, and machines that were asleep
when a commit landed.

One daemon replaces the three per-platform timers that previously implemented
scheduling, jitter, locking, and retry separately. Worst-case latency from push
to convergence drops from about a day to about ten minutes.

## Announcements

Polling GitHub from every host spends GitHub's 60 unauthenticated requests an
hour per IP, which hosts behind one NAT share. So CI tells the hosts instead:

1. The `announce` step of the push pipeline on master runs after every other
   step has passed. It signs `{repo, ref, sha, seq, time}` with an ed25519
   key (the Woodpecker secret `rollout_signing_key`), `seq` being the
   pipeline number, and publishes it with `dotfiles-upgraded announce` to the
   ntfy topic in `flake.lib.rollout`. The relay runs in the cluster
   (clusters-work, `docs/ntfy.md`); only the CI token may publish.
2. Each daemon holds a stream to the topic (`--notify-url`, with
   `since=latest`, so a host that reconnects gets the newest announcement it
   missed). It checks the signature against `--notify-public-key`, the repo
   and the ref, and switches without asking GitHub.

The relay is untrusted. It can delay or drop announcements but not forge one,
and it cannot roll a host back: the daemon takes an announcement only when its
`seq` is above the last one it took (`announcedSeq` in `state.json`), and CI
announces a commit only while it is still the tip of master, so a rerun of an
older pipeline is not announced under a newer number.

Announcing is a step of the push pipeline, so a failed announcement fails the
pipeline. GitHub therefore never reports success on a commit that was not
announced, and the two paths cannot disagree: the newest announcement is never
older than a commit the GitHub path switched to.

While the stream is up, GitHub is only the fallback for a lost announcement and
is asked every `--notified-poll-interval` (6h). Once the stream has been down
for 5 minutes (a relay restart stays under that), the daemon is woken and polls
every `--poll-interval` until the stream returns. Hosts off the tailnet turn
announcements off and poll as before.

## Cycle

An announcement taken since the last tick switches the host and ends the
cycle, as described above. Otherwise each tick asks GitHub for the tip of the tracked branch, sending the stored
`ETag` as `If-None-Match`. A `304` or an unchanged SHA ends the cycle without
further requests. A new SHA is gated on the commit statuses of its push
pipeline (`ci/woodpecker/push/*`). The cron and manual pipelines report on the
same commit but run only the update jobs, so their verdict neither rejects nor
approves it:

- `success` from every push workflow switches the host.
- `failure` gives up on that SHA immediately.
- `pending` waits. CI not having finished is not a verdict, so the SHA is
  retried on later ticks until it resolves, is superseded, or exceeds
  `--pending-timeout`. A commit with no push status yet counts as pending.

A failing switch retries with exponential backoff up to `--max-attempts`, then
the SHA joins a small ignore set. A transient fault and a genuinely broken
commit are indistinguishable by exit code, so retrying lets transients heal
while the ignore stops one bad commit from blocking the next one. Ignoring is
safe because the daemon targets the branch tip rather than a queue: a skipped
commit is simply superseded.

The last _successfully applied_ SHA is what gets persisted, never the last one
seen. A host interrupted mid-switch retries rather than believing it converged.
A successful switch clears the ignore set.

The rebuild holds an exclusive advisory lock for its whole duration, so two
daemon cycles cannot race. A manual rebuild does not take this lock; the Nix
store's own locking serialises the builds. The lock wait obeys the switch
timeout and SIGTERM, and cancellation signals the rebuild's whole process group. Child stdout and stderr are folded into the
daemon's structured log, which is where an unattended failure leaves its trace.

The Linux units restart the daemon behind the same lock when a switch changes
them (`upgraderReload` in `fleet.nix`), so a new build replaces the daemon
only after the rebuild that delivered it has finished. SIGTERM only cancels the
daemon's context, so a restart that arrives as the lock is released still lets
it record that rebuild.

## Rate limits

Conditional requests are used whether or not a credential is present.
Unauthenticated operation is a supported mode, not a degraded fallback. With
announcements a host makes a request every 6 hours, plus one each time the
daemon restarts; without them, one every 10 minutes, which several hosts
behind one address can exhaust.
Setting `GITHUB_TOKEN` raises the budget to 5000/hr per token and makes
steady-state `304`s free, which matters when several hosts share one address.

A `403` or `429` backs off using `Retry-After` or `X-RateLimit-Reset` when
present. An `X-Poll-Interval` header raises the interval floor. Ticks are
jittered per host so the fleet does not poll in lockstep.

Waits between ticks are measured in wall-clock time. A host that sleeps through
a deadline polls within a minute of waking, rather than resuming a timer that
stopped counting while it was suspended.

## State directory

`--state-dir` holds three files:

| File          | Purpose                                                                    |
| ------------- | -------------------------------------------------------------------------- |
| `state.json`  | ETag, last applied SHA, ignore set and reasons, undelivered failure report |
| `status.json` | health signal, rewritten after every cycle and around each attempt         |
| `lock`        | exclusive lock held during a rebuild                                       |

A missing or corrupt `state.json` starts fresh with a logged warning; refusing
to start would strand the host permanently. Both files are written through a
temporary file and renamed, so a crash mid-write cannot truncate them.

## Health

`status.json` is the only signal that an unattended host is still converging:

```json
{
  "updatedAt": "2026-09-17T04:24:03Z",
  "lastCheck": "2026-09-17T04:12:03Z",
  "phase": "up-to-date",
  "phaseSince": "2026-09-17T04:12:03Z",
  "tipSha": "…",
  "nextCheck": "2026-09-17T04:22:41Z",
  "lastSuccessSha": "…",
  "lastSuccessAt": "2026-09-17T04:12:03Z",
  "lastError": null,
  "consecutiveFailures": 0,
  "ignoredShas": [],
  "notify": {
    "connected": true,
    "lastEventAt": "2026-09-17T04:21:58Z",
    "announcedSeq": 4321
  }
}
```

`phase` says what the daemon is doing about `tipSha`, the tip of the tracked
branch, and `phaseSince` when it started:

| Phase           | Meaning                                                  |
| --------------- | -------------------------------------------------------- |
| `up-to-date`    | the tip is applied                                       |
| `awaiting-ci`   | the tip has no CI verdict yet                            |
| `switching`     | a rebuild of the tip is running                          |
| `retrying`      | a rebuild failed; the next attempt starts at `nextCheck` |
| `check-failed`  | GitHub could not be asked about the tip                  |
| `ci-failed`     | CI rejected the tip                                      |
| `ci-timed-out`  | CI stayed pending past `--pending-timeout`               |
| `switch-failed` | every rebuild attempt failed                             |

The last three ignore the tip, so the host stays where it is until a newer
commit lands. The reason is persisted with the ignore set, so a restarted
daemon still reports it.

`notify` is present when the daemon subscribes to announcements. `lastEventAt` is the last line
the relay sent, keepalives included (every 45 seconds), so one more than a few
minutes old with `connected` true means a stalled stream the daemon has yet to
replace; the daemon replaces one silent for 3 minutes.

`nextCheck` is when the daemon next acts, and is null while a rebuild runs.
`lastCheck` and `nextCheck` change only when the daemon decides something;
while it waits, it rewrites the file every 2 minutes with only `updatedAt` and
`notify` changed. An `updatedAt` more than a few minutes old outside a rebuild
means the daemon has stopped, or the host has just woken and the daemon has yet
to catch up. The login banner (`packages/motd`)
shows this state on every host whose auto-upgrade is enabled.

Inspect it with:

```sh
jq . /var/lib/dotfiles-upgraded/status.json          # nixos and darwin
jq . "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-upgraded/status.json"
```

A rising `consecutiveFailures` with a non-null `lastError` is the condition
worth alerting on. Both are kept in memory and cleared only when the host
reaches the tip, so a host stranded behind an ignored commit keeps reporting
the failure that stranded it.

## Failure reports

When the daemon gives up on a commit after `--max-attempts` failed rebuilds, it
posts the commit, the last error, and the last 40 lines of rebuild output to
`--failure-webhook`. The webhook is the n8n workflow in
[`n8n/failure-report.json`](n8n/failure-report.json). It opens one GitHub issue
per commit, as the Whexy Bot GitHub App, and every further host that gives up
on the same commit adds a `+1` comment. The workflow finds the issue by a
hidden `<!-- dotfiles-upgraded sha=… -->` marker in its body among the open
issues. GitHub's issue list shows a new issue only seconds after it is opened,
so the workflow also remembers the issues it opened in the last hour. Once
that hour has passed, closing an issue lets a later failure on the same commit
open a new one.

Only rebuild failures are reported. A CI failure already shows on the commit,
and every host would report it.

Hosts carry the webhook's bearer token, `secrets/upgrade-webhook-token.age`,
not a GitHub credential. The report is saved in `state.json` until the webhook
accepts it, and delivery is retried every cycle. Only a `400`, `413` or `422`
drops it, because those mean the request itself is malformed. A newer failure
replaces an undelivered one.

The report cannot notice a daemon that has stopped, or a host that never sees a
new commit. `status.json` remains the signal for those.

### Deploying the workflow

The workflow references two n8n credentials by placeholder ID; replace them
with real IDs when importing it on the tailnet editor
(`https://n8n.at-basking.ts.net`):

- `WEBHOOK_CREDENTIAL_ID`, a Header Auth credential named
  `dotfiles-upgraded webhook token`: header `Authorization`, value
  `Bearer <token>`, where `<token>` is the decrypted
  `upgrade-webhook-token.age`.
- `GITHUB_APP_CREDENTIAL_ID`, the GitHub App API credential
  `GitHub Whexy Bot (whexy)`, which needs Issues: read and write on
  `whexy/dotfiles`. Issues come from the app's bot account, so GitHub notifies
  the repository's watchers; an issue opened with the owner's own token would
  not.

To rotate the token, re-encrypt the secret (`agenix -e
upgrade-webhook-token.age`) and update the Header Auth credential. Until both
match, reports wait in `state.json`.

## Flags

| Flag                           | Default                 | Meaning                                          |
| ------------------------------ | ----------------------- | ------------------------------------------------ |
| `--mode`                       | required                | `nixos`, `darwin`, or `home-manager`             |
| `--configuration`              | required                | flake output name, e.g. `mudd` or `wenxuan@mars` |
| `--state-dir`                  | required                | directory for the files above                    |
| `--flake`                      | `github:whexy/dotfiles` | flake reference to switch to                     |
| `--repo`                       | `whexy/dotfiles`        | GitHub owner/name for API queries                |
| `--ref`                        | `master`                | tracked branch                                   |
| `--poll-interval`              | `10m`                   | base interval between ref checks                 |
| `--max-attempts`               | `3`                     | switch attempts before a commit is ignored       |
| `--require-ci-pass`            | `true`                  | only switch to commits whose status is success   |
| `--switch-timeout`             | `6h`                    | hard limit on a single rebuild                   |
| `--pending-timeout`            | `2h`                    | give up on a commit whose CI stays pending       |
| `--failure-webhook`            | none                    | URL to post a commit the host gave up on         |
| `--failure-webhook-token-file` | none                    | file holding that webhook's bearer token         |
| `--notify-url`                 | none                    | ntfy topic URL carrying CI's announcements       |
| `--notify-public-key`          | none                    | base64 ed25519 key announcements are signed with |
| `--notified-poll-interval`     | `6h`                    | ref check interval while the stream is healthy   |

The mode is configured rather than autodetected, so a misdetection cannot
switch a host the wrong way. The flake ref is pinned to the gated commit so
the host builds exactly what CI approved. The rebuild command per mode:

```sh
nixos-rebuild switch --refresh --flake <flake>/<sha>#<configuration>
darwin-rebuild switch --refresh --flake <flake>/<sha>#<configuration>
nh home switch <flake>/<sha> --refresh --no-nom -c <configuration> -b backup
```

`PATH` must contain `git` and Nix. Runtime failures are retried and recorded;
the process exits non-zero only on a bad configuration.

Build parallelism is not a flag: the daemon runs whatever rebuild it is given,
and the modules throttle it by exporting `NIX_CONFIG` (`max-jobs`, `cores`) in
the service environment, so an unattended rebuild is capped while a manual one
still uses the machine default. Where those builds run depends on the caller.
As root, Nix opens the store directly, so in `nixos` mode and for a root Home
Manager the builds run inside the daemon's own unit, which the modules give a
low CPU and I/O weight. `darwin-rebuild` and an unprivileged user go through
`nix-daemon` instead, which receives the settings over the socket and runs the
builds itself; only evaluation stays with the daemon.

`dotfiles-upgraded announce --url <topic URL> --sha <sha> --seq <n>
[--public-key <key>]` is the CI side. It reads the signing key (a base64
32-byte ed25519 seed) from `ROLLOUT_SIGNING_KEY` and the relay's token from
`NTFY_ROLLOUT_TOKEN`, and refuses to publish when `--public-key` does not
match the key, since hosts would reject what it signs.

### Rotate the signing key

Generate a seed and its public key, update the Woodpecker secret, then at once
commit the public key to `flake.lib.rollout.publicKey` (`fleet.nix`) and push: `announce`
checks the secret against the key of the commit it announces, so a commit that
lands between the two fails its pipeline. Hosts verify with
the key their current generation carries, so the commit that changes it is
not announced to them in a form they accept; they reach it through the GitHub
fallback (6h at most), and take announcements again from then on.

```sh
umask 077; head -c 32 /dev/urandom | base64 -w0 > seed
{ printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'; base64 -d seed; } |
  openssl pkey -inform DER -pubout -outform DER | tail -c 32 | base64 -w0   # public key
woodpecker-cli repo secret update --repository whexy/dotfiles --name rollout_signing_key --value @seed
rm seed
```

## Verification

```sh
nix build .#dotfiles-upgraded --no-link
```
