---
name: darwin-updater-onboarding
description: How to bring a new macOS host under the dotfiles-upgraded auto-update daemon - installing and signing the root-owned Dotfiles Updater.app, granting Full Disk Access, ordering the upstream commit against the bootstrap switch, and verifying a real daemon-driven activation. Read before adding a Darwin host with dotfiles.system.autoUpgrade.enable, replacing the launcher, or debugging an auto-update daemon that never switches.
---

# Onboarding a macOS host to the auto-updater

On NixOS a host joins the fleet by landing a commit. On Darwin it cannot: one
artifact must be installed by hand on each machine before the daemon works.

## Why a manual install exists

`/Applications/Dotfiles Updater.app` is a tiny signed C launcher
(`packages/dotfiles-upgraded/darwin-launcher/launcher.c`) whose only job is to
be a **stable TCC identity**. It execs
`/run/current-system/sw/bin/dotfiles-upgraded-service`, waits, and relaunches it
after exit.

Three constraints force it out of Nix:

- Full Disk Access is granted to a code signature at a fixed path. Nix store
  paths change on every upgrade, so a store-resident binary would lose its grant
  constantly and re-prompt for authentication.
- The launchd plist in `modules/hosts/system/darwin.nix` deliberately contains
  no store path. If activation rewrote the plist, launchd would unload the
  daemon in the middle of the switch that daemon is supervising.
- The signing identity is a local bootstrap asset. It is not in the flake and
  not available to CI.

So the app, its signing key, and the per-machine TCC grant are outside the
declarative system. Everything else — the entrypoint script, the daemon binary,
the plist — is Nix-managed and updates itself.

## Procedure for a new host

Order matters. Step 4 before step 5 is not stylistic; see the trap below.

### 1. Obtain the signed bundle

Prefer copying from a Mac already in the fleet, which keeps one signing
requirement across hosts:

```sh
scp -rp '/Applications/Dotfiles Updater.app' newmac:/tmp/
```

Otherwise rebuild it with the persistent codesigning identity:

```sh
security find-identity -v -p codesigning
bash packages/dotfiles-upgraded/darwin-launcher/build.sh \
  /tmp/dotfiles-updater-production SIGNING_IDENTITY_HASH
```

The output directory must not already exist and the identity must not be `-`;
ad-hoc signatures do not persist a TCC grant across replacement builds.

### 2. Install as root

```sh
sudo ditto '/tmp/Dotfiles Updater.app' '/Applications/Dotfiles Updater.app'
sudo chown -R root:wheel '/Applications/Dotfiles Updater.app'
sudo chmod -R go-w '/Applications/Dotfiles Updater.app'
sudo chmod 755 '/Applications/Dotfiles Updater.app/Contents/MacOS/dotfiles-updater-launcher'
codesign --verify --strict '/Applications/Dotfiles Updater.app'
```

Never symlink it out of a user-writable checkout; a writable responsible process
is not a trustworthy identity. The explicit `chmod 755` is required even after
`scp -rp`, which can drop the executable bit. If launchd already failed to spawn
a non-executable launcher, `bootout` and `bootstrap` the job after fixing the
mode rather than `kickstart`.

### 3. Grant Full Disk Access

System Settings → Privacy & Security → Full Disk Access → **+** →
`/Applications/Dotfiles Updater.app`, then enable it.

TCC grants are per-machine and per-identity. Copying a bundle byte-for-byte from
a Mac that already has the grant does not carry the grant with it. A grant held
by _Dotfiles Updater Probe_ (the separate FDA experiment under
`packages/dotfiles-upgraded/fda-probe/`) does not transfer either. Grant the app
itself — not Bash, not a Nix store binary, not the terminal.

### 4. Land the host config upstream first

```nix
# hosts/<name>/darwin-configuration.nix
dotfiles.system.autoUpgrade.enable = true;
```

Push it to the tracked branch and let CI pass **before** the daemon ever runs.
The daemon converges on upstream `master`, not on the local checkout. Start it
against an upstream that does not yet enable auto-upgrade for this host and its
first successful switch disables the service, leaving a machine that looks
installed and silently never updates again.

`configuration` defaults to `config.dotfiles.host.hostName`. Set it explicitly
when the flake output name differs from the runtime hostname.

### 5. One authenticated bootstrap switch

```sh
nix build .#darwinConfigurations.<name>.system --out-link /tmp/<name>-bootstrap
sudo /tmp/<name>-bootstrap/sw/bin/darwin-rebuild switch --flake .#<name>
```

This installs the plist and the entrypoint. It is the last switch that needs
your presence.

### 6. Verify a daemon-driven switch

A running job is not the success criterion.

```sh
launchctl print system/org.nixos.dotfiles-upgraded
tail -n 80 /var/log/dotfiles-upgraded.log
jq . /var/lib/dotfiles-upgraded/status.json
```

Require a `switched` log entry together with a matching `lastSuccessSha` in
`status.json`. The foreground switch in step 5 can succeed on the terminal's own
privacy permission, so it is no evidence at all about the daemon's FDA
attribution. An empty `lastError` alone does not establish that a switch
happened.

## Steady state and lifecycle

The daemon runs with `--exit-after-switch`: after recording success it exits so
the launcher re-execs the _new_ system's entrypoint. Routine updates therefore
touch only the Nix-managed entrypoint and daemon binary — not the plist, not the
signed app — and need no manual step.

Manual steps return only when:

- **Replacing the launcher.** Stop the daemon first, replace the app, then start
  it. Do not hot-swap the binary under a live job.
- **Rotating the signing certificate**, or **after a macOS upgrade**. Re-verify a
  complete daemon-driven activation afterwards. The FDA probe exercises only part
  of the activation chain and is not sufficient proof.
- **Changing the plist or disabling auto-upgrade.** An unattended switch that
  rewrites the plist can unload the job performing it. Make lifecycle changes
  through an interactive maintenance switch.

Control the job explicitly with:

```sh
sudo launchctl bootout system/org.nixos.dotfiles-upgraded
sudo launchctl bootstrap system /Library/LaunchDaemons/org.nixos.dotfiles-upgraded.plist
```

## Diagnosing a host that never switches

Work down this list; each item explains a distinct silent failure.

| Symptom                                                 | Likely cause                                                                                              |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| Job absent from `launchctl print`                       | bootstrap switch (step 5) never ran                                                                       |
| `start dotfiles-upgraded-service` / exit 127 in the log | entrypoint missing — host built without `autoUpgrade.enable`, or launcher mode is not 755                 |
| Log shows candidate SHAs but never `switched`           | CI gate: status `pending` or `failure` upstream, or the SHA reached the ignore set after `--max-attempts` |
| Switch fails at Home Manager activation                 | FDA grant missing or attributed to the wrong identity                                                     |
| Worked once, then went quiet                            | converged onto an upstream commit where this host has auto-upgrade disabled (the step-4 ordering trap)    |
| `consecutiveFailures` rising with non-null `lastError`  | the condition actually worth alerting on                                                                  |

Background on the daemon's own state machine, CI gating, backoff, and rate
limiting lives in `packages/dotfiles-upgraded/README.md`; the launcher and its
installation are documented in
`packages/dotfiles-upgraded/darwin-launcher/README.md`.
