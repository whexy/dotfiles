# Design: `dotfiles-upgraded` — a unified auto-upgrade daemon

Status: accepted, implemented (package + modules); per-host rollout pending
Author: design discussion, 2026-09-17
Scope: replaces all three existing auto-upgrade mechanisms

## 1. Problem

Auto-upgrade is currently implemented three times, once per platform:

| Platform      | Implementation                                                                   | Schedule                                                                 |
| ------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| NixOS         | `system.autoUpgrade` (`nixos-upgrade.timer`) in `modules/hosts/system/nixos.nix` | 04:00, `persistent`, `randomizedDelaySec = 45min`                        |
| Darwin        | root launchd daemon in `modules/hosts/system/darwin.nix`                         | 04:00 via `StartCalendarInterval`, jitter via `sleep $((RANDOM % 2700))` |
| Standalone HM | user systemd timer in `modules/home/auto-upgrade/default.nix`                    | 05:00, `Persistent`, `RandomizedDelaySec = 45min`                        |

Problems with the status quo:

1. **Scheduling logic is written three times** in three dialects. The Darwin
   `sleep $((RANDOM % 2700))` is a hand-rolled reimplementation of systemd's
   `randomizedDelaySec`; launchd has no equivalent.
2. **Failures are silent.** Nothing reports a failed 04:00 rebuild. A host can
   stop updating indefinitely and nothing surfaces it.
3. **Latency is up to 24h.** A pushed fix reaches the fleet at 04:00 the next
   morning.
4. **The trigger is wrong.** The timer fires daily regardless of whether
   anything changed. Because `upstreamRef` is pinned by `flake.lock`, rebuilding
   the same commit yields an identical closure, so most runs are no-ops.
5. **The HM variant has a silent failure mode**: the user manager stops at
   logout unless `loginctl enable-linger` was run manually, which is documented
   only in a source comment.

## 2. Goals and non-goals

### Goals

- One implementation of scheduling, jitter, locking, logging, and retry.
- Low latency from push to fleet convergence (~10 min, versus up to 24h today).
- Real failure reporting for unattended runs.
- Cover **all** supported host classes: NixOS, nix-darwin, standalone Home
  Manager.
- No inbound network surface.

### Non-goals

- **Central building / closure pushing.** The fleet spans `x86_64-linux`,
  `aarch64-linux`, and `aarch64-darwin`; no single builder covers all three.
  Hosts keep building locally, with `whexy.cachix.org` absorbing shared work.
- **Rollback on failure.** A failed switch is already harmless (Nix keeps the
  running generation). Automatic rollback fights interactive debugging.
- **Replacing CI.** The daemon consumes the CI verdict; it does not re-run it.

## 3. Rejected alternatives

Recorded because each was considered and rejected for a specific reason.

### 3.1 SSH push (`nixos-rebuild --target-host`, colmena, deploy-rs)

- Cannot build `aarch64-darwin` and both Linux arches from one host.
- Does not cover standalone HM hosts (`venus`, `mars`, `b3srv0`, `proxmox`),
  which are not NixOS, so a second mechanism would survive anyway.
- Deploys the pusher's working tree rather than a reviewed commit.

### 3.2 SSH-triggered pull (forced-command key that starts the existing unit)

Better than 3.1, but rejected because it cannot reach large parts of the fleet:

- `mudd` is reachable only through Cloudflare Access.
- Laptops are behind NAT and are usually asleep.
- Requires per-platform trigger incantations (`systemctl start --wait`,
  `launchctl kickstart`), i.e. it preserves the divergence this design removes.

### 3.3 Inbound listener on each host

Rejected. A listening daemon that triggers a root rebuild must reimplement
authentication, transport security, and replay protection; a bug there is
remote root. It also cannot be reached on NAT'd or Cloudflare-only hosts.

### 3.4 Commit-signature gating

Rejected by explicit decision. The GitHub account is protected with hardware
keys and MFA. Two supporting points:

- This is **parity with today**: the current `--refresh` pull already trusts
  whatever GitHub serves.
- Signature gating collides with the nightly `update-flake` CI job, which
  commits `flake.lock` as `whexy-bot[bot]` using a GitHub App token. Those
  commits are not signed with the personal key.

Consequence to accept knowingly: the effective trust set is **GitHub account ∪
Woodpecker CI secrets**, because the App private key can push to `master`.
Content-scoping bot commits (e.g. "bot may only touch `flake.lock`") is _not_
enforceable without signatures, since author fields are free text.

Recommended server-side mitigations (outside the daemon, not blocking):

- Branch protection on `master` requiring the Woodpecker status to pass.
- Scope the GitHub App token to `contents:write` on this repository only.

## 4. Design

A single Go daemon, `dotfiles-upgraded`, runs on every host. It polls the
upstream repository over HTTPS, and switches when a new commit on `master`
has passed CI. It never accepts an inbound connection.

```
                   ┌──────────────── GitHub ────────────────┐
                   │  refs/heads/master   commit status API │
                   └───▲────────────────────────▲───────────┘
                       │ conditional GET (ETag) │
                       │                        │
   ┌───────────────────┴────────────────────────┴───────────┐
   │                  dotfiles-upgraded                     │
   │  poll → gate → switch → record                         │
   └────────────────────────────────────────────────────────┘
        NixOS            Darwin              standalone HM
   nixos-rebuild    darwin-rebuild        nh home switch
```

### 4.1 Why polling beats push

Outbound polling reaches hosts that no push mechanism can: NAT'd laptops,
Cloudflare-only `mudd`, and sleeping machines (which pick up changes on wake
without needing catch-up logic). Conditional GET with an `ETag` costs a few
hundred bytes when nothing changed, so a 10 min interval is nearly free while
still cutting worst-case latency from ~24h to ~10 min, with zero inbound
surface.

The interval is deliberately unaggressive. CI must finish before a commit is
eligible anyway (§4.3), and that dominates end-to-end latency, so polling
faster than the CI pipeline would mostly produce `pending` results.

### 4.2 Tracked ref

`refs/heads/master` of `github:whexy/dotfiles`.

> Note: the default branch is **`master`**, not `main`. `flake.lib.upstreamRef`
> (`github:whexy/dotfiles`) resolves to it implicitly; the daemon names it
> explicitly.

A separate promoted `deploy` branch was considered and rejected: CI is the
gate, and `git revert` + push converges the fleet for rollback.

### 4.3 Gate

A commit is eligible iff the **GitHub commit status / check state for that SHA
is success**. Signature verification is deliberately absent (§3.4).

The daemon reads commit status from the GitHub API rather than Woodpecker's:
Woodpecker already reports status back to GitHub, so no second credential path
or API client is needed.

### 4.4 Authentication and rate limits

At a 10 min interval, **authentication is an optimisation rather than a
requirement**. Per GitHub's REST API best-practices documentation:

> Making a conditional request does not count against your primary rate limit
> if a `304` response is returned **and the request was made while correctly
> authorized with an `Authorization` header**.

So `304` responses are free only when authenticated. The budgets:

| Mode            | Cost at 10 min                                          | Limit             | Headroom    |
| --------------- | ------------------------------------------------------- | ----------------- | ----------- |
| Unauthenticated | ~6 ref checks/hr, plus a CI-status check per new commit | 60/hr **per IP**  | comfortable |
| Authenticated   | ~0 (steady-state `304`s are free)                       | 5000/hr per token | irrelevant  |

Unauthenticated operation therefore fits, but the per-IP limit is shared: the
Incus guests on `mars` (`deimos` and siblings) count against one budget, as do
any hosts behind a common NAT. Several hosts at ~6-12 req/hr still fit inside
60/hr, though the margin shrinks as the fleet grows behind a single IP.

Requirements:

- Use conditional GET with `ETag` / `If-None-Match` regardless of auth; it
  saves bandwidth either way and makes `304`s free once authenticated.
- Authenticate when a credential is available (`nix-gh-token` /
  `github-app-token` already exist in this repo), which removes the shared-IP
  concern entirely.
- Operate correctly **without** a credential — this is a supported mode, not a
  degraded fallback, and must not fail closed.
- Honour the `x-poll-interval` response header when present; GitHub raises it
  under load and expects clients to obey.
- Jitter the interval per host to avoid a synchronised thundering herd.
- Back off on `403`/`429` rather than hammering.

### 4.5 State machine

```
            ┌─────────┐
            │  Idle   │◄────────────────────────────┐
            └────┬────┘                             │
                 │ poll tick                        │
                 ▼                                  │
        ┌──────────────────┐  304 / same SHA        │
        │  Check ref HEAD  │────────────────────────┤
        └────────┬─────────┘                        │
                 │ new SHA                          │
                 ▼                                  │
        ┌──────────────────┐  pending → wait        │
        │  Check CI status │  failure → ignore SHA ─┤
        └────────┬─────────┘                        │
                 │ success                          │
                 ▼                                  │
        ┌──────────────────┐                        │
        │     Switch       │                        │
        └────┬────────┬────┘                        │
       ok    │        │  error                      │
             ▼        ▼                             │
    ┌────────────┐  ┌──────────────────┐            │
    │ Record SHA │  │ Backoff & retry  │            │
    └─────┬──────┘  │ (max N attempts) │            │
          │         └────────┬─────────┘            │
          │                  │ exhausted            │
          │                  ▼                      │
          │         ┌──────────────────┐            │
          │         │  Ignore this SHA │            │
          │         └────────┬─────────┘            │
          └──────────────────┴─────────────────────►┘
```

Key invariants:

1. **Record only on success.** Persisted state is the last _successfully
   applied_ SHA, never the last _seen_ SHA. This is what replaces
   `persistent = true`.
2. **Bounded retries, then ignore.** A transient failure (cache outage, DNS
   blip, full disk) is indistinguishable from a bad commit by exit code alone.
   Retry with exponential backoff up to `maxAttempts`, then add the SHA to an
   ignore set. This preserves "a failed commit is ignored" while letting
   transients heal.
3. **Ignoring is safe because the daemon targets HEAD, not a queue.** A skipped
   commit is superseded by the next one; there is no backlog and no replay.
4. **Ignore set is bounded** (small ring buffer) and cleared on a successful
   switch.
5. **`pending` CI is not a failure.** Keep polling until the status resolves,
   the SHA is superseded, or `pendingTimeout` (default 2h, well above the
   pipeline's duration) elapses, after which the SHA is ignored so a status
   that never reports cannot pin the host forever.

### 4.6 Per-platform switch command

The only platform-specific surface. Selected by configuration, not autodetection.

| Mode           | Command                                                                            |
| -------------- | ---------------------------------------------------------------------------------- |
| `nixos`        | `nixos-rebuild switch --refresh --flake <upstreamRef>/<sha>#<configuration>`       |
| `darwin`       | `darwin-rebuild switch --refresh --flake <upstreamRef>/<sha>#<configuration>`      |
| `home-manager` | `nh home switch <upstreamRef>/<sha> --refresh --no-nom -c <user>@<host> -b backup` |

These are the commands in use today with one change: the flake ref is pinned
to the gated SHA. An unpinned ref would build whatever the branch tip is when
the build starts, so a commit landing mid-cycle could bypass the CI gate and
`lastSuccessSha` would not name what was actually applied.

Requirements:

- Stream child stdout/stderr into the daemon's structured log.
- Apply a generous timeout (a cold build can take a long time; the timeout
  guards against a genuinely wedged process, so default it high, e.g. 6h).
- Hold an exclusive advisory lock for the duration so two daemon cycles (or a
  restart during a switch) cannot contend on the Nix store lock. A manual
  `nixos-rebuild` does not take this lock; the Nix store's own locking still
  serialises the builds.
- `PATH` must include `git` and Nix. The existing HM module has a hard-won
  `PATH` workaround for this (`nix.package` is null on generic-Linux hosts;
  `~/.nix-profile/bin` and `/nix/var/nix/profiles/default/bin` must be added
  explicitly). **Carry that logic over.**

### 4.7 Health signal

Because failures are otherwise silent, the daemon writes a status file after
every cycle (path configurable; default under `/var/lib/dotfiles-upgraded/` for
system modes and `$XDG_STATE_HOME/dotfiles-upgraded/` for HM mode):

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

This is the hook for later alerting. `dotfiles.monitoring.*` already exists as
the natural place to surface it; wiring that up is out of scope for v1.

## 5. Implementation

### 5.1 Language and layout

Go, per decision. A static binary has no runtime dependency on a host
interpreter, which matters because this is the one component whose failure
cannot be repaired by pushing a commit (§7).

Blueprint maps `packages/<pname>/default.nix` to
`packages.<system>.<pname>` **and** `checks.<system>.pkgs-<pname>`, so tests
run in CI automatically.

```
packages/dotfiles-upgraded/
  default.nix        # pkgs.buildGoModule, doCheck = true
  go.mod
  main.go
  internal/…
  README.md          # follows packages/ssh-agent-router/README.md
```

Note: this is the repo's **first `buildGoModule` package**; there is no
existing Go pattern to copy. `vendorHash` will need to be filled in.

### 5.2 Testing

`ssh-agent-router` sets the precedent (`doCheck = true`, `nativeCheckInputs`,
real unit tests). Match it. Because this daemon runs as root and performs
system switches, tests are a requirement, not a nicety:

- State machine transitions: new SHA, same SHA, CI pending/failure/success,
  switch success/failure, retry exhaustion, ignore-set behaviour.
- Backoff schedule and bounds.
- Conditional-GET handling: `200` vs `304`, ETag persistence.
- Rate-limit fallback when unauthenticated.
- State file round-trip, including corrupt/missing file recovery.
- Switch invocation is behind an interface so tests never shell out.

### 5.3 Nix module surface

Extend the existing groups; do not introduce a new semantic group. Auto-upgrade
is a property of the `system` group (and the HM `autoUpgrade` module), so the
existing option names stay and gain fields.

System (`modules/hosts/system/default.nix`), keeping
`dotfiles.system.autoUpgrade.{enable,configuration}` as they are:

```nix
dotfiles.system.autoUpgrade = {
  # existing: enable, configuration
  pollInterval   = mkOption { type = types.str;  default = "10m"; };
  maxAttempts    = mkOption { type = types.int;  default = 3; };
  requireCiPass  = mkOption { type = types.bool; default = true; };
};
```

- `modules/hosts/system/nixos.nix`: replace the `system.autoUpgrade` block
  with a `systemd.services.dotfiles-upgraded` long-running unit
  (`Restart = "always"`). **Remove** the `system.autoUpgrade` usage so the
  stock `nixos-upgrade.timer` does not run alongside the daemon.
- `modules/hosts/system/darwin.nix`: replace the launchd daemon script with
  a `KeepAlive` daemon invoking the binary. The `sleep $((RANDOM % 2700))`
  jitter hack disappears (the daemon jitters internally).
- `modules/home/auto-upgrade/default.nix`: replace the timer with a
  long-running user service. **Keep** the existing `<user>@<host>` path-based
  deduction and the `PATH` construction; both encode real constraints. Keep the
  `loginctl enable-linger` note — it matters more now, not less, since a
  long-running service is useless without it.

### 5.4 Migration

Per-host, not fleet-wide at once:

1. Land the package with tests (inert; nothing references it).
2. Convert one low-risk NixOS host (`mudd` or `deimos`), watch the state file.
3. Convert one Darwin host, then one standalone HM host.
4. Roll out the rest.

The old and new mechanisms **must not** both be enabled on a host: two
concurrent `nixos-rebuild` invocations would contend on the Nix store lock.
The module changes in §5.3 replace rather than add, which enforces this.

Because hosts pull, a host converts itself when it picks up the commit
enabling the daemon on it.

Rollout record (2026-09-17): NixOS (`mudd`) and standalone HM (`venus`)
converted and completed an unattended switch. **Darwin is not enabled on any
host.** An unattended `darwin-rebuild switch` from a root launchd daemon fails
during Home Manager activation with `Operation not permitted` on files under
`~/Library/Application Support` (TCC: the daemon lacks the Full Disk Access
that an interactive terminal has); the same class of failure (Homebrew
prompting for sudo, protected paths) is why the previous Darwin calendar job
was also left disabled. The daemon itself behaved correctly on `golf`: it
streamed the activation log, retried with backoff, and would have ignored the
SHA after `maxAttempts`. Fixing Darwin unattended activation is a separate
task; until then Darwin hosts are upgraded manually.

## 6. CI implications

`.woodpecker.yml` becomes load-bearing: it is the gate on what reaches the
fleet.

**A build failure is not a safety concern.** `nixos-rebuild switch` (and the
Darwin and HM equivalents) build the full closure before activating anything,
so a commit that fails to compile cannot be switched to: the host stays on its
running generation and §4.5's retry-then-ignore handles it. CI evaluating
rather than building is therefore an **efficiency** matter, not a gate
weakness — the cost is that every host independently rediscovers the failure by
attempting its own build, and feedback arrives at the fleet instead of in CI.
Adding `nix build` for representative hosts is a reasonable later improvement,
not a prerequisite.

One genuine gap remains: **coverage is representative, not complete.**
Evaluated today: `mudd`, `ellison`, `wsl`, `golf`, `sheridan`, `wenxuan@mars`.
Not evaluated: `deimos`, `neith`, `phobos`, `zoozve`, `moore`, `skokie`,
`b3srv0`, `proxmox`, `venus`. `deimos` in particular carries an nvidia module
that nothing checks. This matters more than eval-vs-build, because an
unevaluated host can take a commit that was never checked in any form.

Adding `packages/dotfiles-upgraded` gives `checks.<system>.pkgs-dotfiles-upgraded`
for free via blueprint, so the daemon's own tests gate every commit.

## 7. Accepted risks

1. **A bad-but-CI-passing commit reaches the whole fleet within ~10 minutes.**
   Explicitly accepted: the grace window is not considered valuable, a failed
   switch leaves the running generation intact, and the real exposure is a
   _successful_ switch to a config that is broken in a way CI cannot see.
2. **A commit that breaks the daemon is self-sealing.** Every other failure is
   repaired by pushing another commit; breaking the updater means no host picks
   up the fix. Same for anything that breaks Tailscale and SSH together.
   Accepted on the grounds that the fleet is ~15 machines and manual repair is
   tractable. Mitigation is engineering discipline, not design: keep the daemon
   dependency-light, unit-tested, and boring.
3. **Trust set includes CI secrets** (§3.4).

## 8. Open questions

- Which credential source should the daemon prefer for GitHub API auth
  (`nix-gh-token` user token vs. `github-app-token`)? System-mode daemons run
  as root and have no `gh` login, so the user-token path may not apply. Per
  §4.4 this is **no longer blocking**: at a 10 min interval the daemon works
  unauthenticated, so v1 can ship without resolving it and add auth later.
- ~~How long should the daemon keep polling a `pending` CI status~~ Resolved:
  `--pending-timeout`, default 2h (§4.5 invariant 5).
- Should `home-manager` mode reuse `nh` or call `home-manager switch` directly?
  `nh` is the current behaviour and is kept for parity, but it adds a
  dependency to the critical path.
- Where should the health/status file be surfaced (`dotfiles.monitoring.*`
  integration), and with what alerting?
