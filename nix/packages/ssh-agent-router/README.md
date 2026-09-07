# SSH agent routing

Ordinary SSH shells retain the forwarded `SSH_AUTH_SOCK` supplied by sshd.
Persistent tmux and Zellij shells use `~/.ssh/ssh-agent.sock`, served by a
small per-user proxy. No private keys are stored by the proxy.

Routing applies only inside an inbound SSH session. On a local desktop the
configured 1Password `IdentityAgent` stays in effect even when a keyring or
gpg-agent exports its own `SSH_AUTH_SOCK`.

Each new forwarded socket is registered when a managed Zsh or Nushell starts
outside a multiplexer. The newest registered socket is preferred. Reopening a
shell with the same socket does not change its priority. The registry survives
daemon restarts; socket paths and device/inode identities identify registrations.
No assumptions are made about OpenSSH's socket directory layout.

The proxy selects one upstream when a client connects and relays the entire
conversation to it. New clients can use a newer registration without disturbing
existing conversations. Missing or connection-refused sockets are evicted and
older registrations are tried. Permission errors, timeouts, missing keys, and
agent refusals do not trigger fallback. A signing request is never replayed.
An upstream disconnect during a conversation fails that operation; retrying it
opens a new connection and can select another agent.

## Office and laptop workflow

1. Connect from the office desktop: the desktop agent is registered.
2. Connect from a laptop and attach to tmux: the laptop agent is newer and wins.
3. Close the laptop connection: subsequent requests fall back to the desktop.
4. Reconnect from the laptop: its new socket takes priority again.

This deliberately trades laptop affinity for availability **inside persistent
sessions only**. A commit in a shared pane may prompt the newest connected
laptop, regardless of which keyboard initiated it. Ordinary SSH shells keep
connection affinity.

An attach using an existing SSH forwarding socket does not promote it. OpenSSH
ControlMaster reuse also does not create a new registration. Connections without
agent forwarding do not change the priority list. Discovery is by registration,
not by scanning other sockets on the host.

## Activation and existing sessions

Rebuild the host/Home Manager configuration, then establish a fresh SSH login.
The first registration starts the detached daemon and replaces the old shared
symlink with the real proxy socket. Already-running panes using that shared path
continue to work without an environment change. Do not source an old, pre-rebuild
shell configuration that still replaces the path with `ln -sf`.

For a pane that has a raw or missing socket, restart its shell after activation
(or explicitly set `SSH_AUTH_SOCK` to `$HOME/.ssh/ssh-agent.sock`). The automatic
pane setup requires `SSH_CONNECTION` inherited from an SSH login; local desktop
multiplexer sessions are left alone. Existing SSH connections from before
activation must run `ssh-agent-router register /original/forwarded/socket` or
reconnect to become registered. The old shared symlink cannot recover every
connection's original socket.

The feature is controlled by `dotfiles.ssh.agentRouter.enable`, which defaults
to `dotfiles.ssh.enable`. Shell integration supports the managed Zsh and Nushell.
Other shells can register an upstream with:

```sh
ssh-agent-router register "$SSH_AUTH_SOCK"
```

The daemon runs without systemd/launchd so it also works in standalone Home
Manager accounts. A lock prevents duplicate daemons; a later shell startup
restarts a dead daemon. State, the PID-bearing daemon lock, and diagnostics live
under `~/.ssh/agent-router/`. The proxy is user-only and does not cross the
existing same-Unix-user trust boundary. It routes live sockets, not agent keys.

## Verification

```sh
nix build .#ssh-agent-router --no-link
```

The package runs its Python unittest suite during the build. Tests cover newest
selection, both disconnect orders, stale socket files, no-agent/reconnect,
duplicate registration, concurrent clients/registration, conversation pinning,
denial behavior, permissions, symlink migration, daemon restart, shell routing,
and real OpenSSH key listing and signing with disposable test keys.
