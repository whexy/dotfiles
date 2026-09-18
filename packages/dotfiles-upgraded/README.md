# Auto-upgrade daemon

`dotfiles-upgraded` keeps one host converged on the upstream dotfiles
repository. It polls `refs/heads/master` over HTTPS, waits for that commit's CI
verdict, and runs the platform's rebuild command. It never accepts an inbound
connection, so it reaches NAT'd laptops, Cloudflare-only hosts, and machines
that were asleep when a commit landed.

One daemon replaces the three per-platform timers that previously implemented
scheduling, jitter, locking, and retry separately. Worst-case latency from push
to convergence drops from about a day to about ten minutes.

## Cycle

Each tick asks GitHub for the tip of the tracked branch, sending the stored
`ETag` as `If-None-Match`. A `304` or an unchanged SHA ends the cycle without
further requests. A new SHA is gated on its combined commit status:

- `success` switches the host.
- `failure` gives up on that SHA immediately.
- `pending` waits. CI not having finished is not a verdict, so the SHA is
  retried on later ticks until it resolves, is superseded, or exceeds
  `--pending-timeout`. A commit with no reported status yet counts as pending.

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

## Rate limits

Conditional requests are used whether or not a credential is present.
Unauthenticated operation is a supported mode, not a degraded fallback: at the
default interval the daemon fits comfortably inside the 60/hr per-IP budget.
Setting `GITHUB_TOKEN` raises the budget to 5000/hr per token and makes
steady-state `304`s free, which matters when several hosts share one address.

A `403` or `429` backs off using `Retry-After` or `X-RateLimit-Reset` when
present. An `X-Poll-Interval` header raises the interval floor. Ticks are
jittered per host so the fleet does not poll in lockstep.

## State directory

`--state-dir` holds three files:

| File          | Purpose                                         |
| ------------- | ----------------------------------------------- |
| `state.json`  | ETag, last successfully applied SHA, ignore set |
| `status.json` | health signal, rewritten after every cycle      |
| `lock`        | exclusive lock held during a rebuild            |

A missing or corrupt `state.json` starts fresh with a logged warning; refusing
to start would strand the host permanently. Both files are written through a
temporary file and renamed, so a crash mid-write cannot truncate them.

## Health

`status.json` is the only signal that an unattended host is still converging:

```json
{
  "lastCheck": "2026-09-17T04:12:03Z",
  "lastSuccessSha": "…",
  "lastSuccessAt": "2026-09-17T04:12:03Z",
  "lastError": null,
  "consecutiveFailures": 0,
  "ignoredShas": []
}
```

Inspect it with:

```sh
jq . /var/lib/dotfiles-upgraded/status.json          # nixos and darwin
jq . "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-upgraded/status.json"
```

A rising `consecutiveFailures` with a non-null `lastError` is the condition
worth alerting on.

## Flags

| Flag                | Default                 | Meaning                                          |
| ------------------- | ----------------------- | ------------------------------------------------ |
| `--mode`            | required                | `nixos`, `darwin`, or `home-manager`             |
| `--configuration`   | required                | flake output name, e.g. `mudd` or `wenxuan@mars` |
| `--state-dir`       | required                | directory for the files above                    |
| `--flake`           | `github:whexy/dotfiles` | flake reference to switch to                     |
| `--repo`            | `whexy/dotfiles`        | GitHub owner/name for API queries                |
| `--ref`             | `master`                | tracked branch                                   |
| `--poll-interval`   | `10m`                   | base interval between ref checks                 |
| `--max-attempts`    | `3`                     | switch attempts before a commit is ignored       |
| `--require-ci-pass` | `true`                  | only switch to commits whose status is success   |
| `--switch-timeout`  | `6h`                    | hard limit on a single rebuild                   |
| `--pending-timeout` | `2h`                    | give up on a commit whose CI stays pending       |

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

## Verification

```sh
nix build .#dotfiles-upgraded --no-link
```

The package runs its Go test suite during the build. Tests cover the state
machine transitions, the backoff schedule and its bounds, conditional GET with
ETag persistence, rate-limit handling with and without a credential, state file
round-trips including corrupt and missing files, and the rebuild exec path. A
fake clock keeps the suite instant, and the engine tests drive a fake switcher
so they never shell out.
