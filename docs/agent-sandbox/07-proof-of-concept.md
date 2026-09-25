# 7. Staged proof of concept

Every stage uses **disposable credentials** on **disposable resources**, has
an exit check, and has a teardown step. Nothing touches production secrets,
the real tailnet policy, or real repositories until stage 4 is reviewed.

| Stage | Adds                                                             | Credentials                              | Needs cluster changes                       |
| ----- | ---------------------------------------------------------------- | ---------------------------------------- | ------------------------------------------- |
| 0     | Agent profile image, leak checks, local tests                    | None                                     | No                                          |
| 1     | Lab deployment on Kubernetes (Sysbox), orchestrator-mediated Git | Throwaway GitHub App on one scratch repo | Lab namespace, Sysbox node                  |
| 2     | Red-team the defaults: egress, DNS, files API, escape surface    | Same                                     | Runner-pod NetworkPolicy                    |
| 3     | Egress proxy and Git proxy; in-sandbox `git push`                | Opaque per-task proxy session tokens     | Runner patch (proxy mode), proxy deployment |
| 4     | One private service via Tailscale ProxyGroup                     | Operator with WIF; tag with one grant    | Operator, tailnet policy change (reviewed)  |

## Stage 0: image and profile (local Docker only)

Build:

1. Implement the `core`/`agent` caps and options from
   [02-profiles.md](02-profiles.md#proposed-module-layout).
2. Switch `hosts/sandbox` to `[ "core" "agent" ]`.
3. Add the pinned `/etc/nix/nix.conf`.

Checks (scriptable as a flake `check` against the image):

```sh
"$(nix build .#sandbox-image --print-out-paths)" | docker load
closure=$(nix path-info -r .#legacyPackages.x86_64-linux.homeConfigurations."user@sandbox".activationPackage)
echo "$closure" | grep -E '\.age$'                        && echo FAIL: ciphertext in closure
docker run --rm --entrypoint /bin/sh n8n-sandbox:latest -c '
  grep -rIl -e "n8n.clusters.work/mcp" -e "whexy@" -e "at-basking" -e agenix -e ForwardAgent \
    /home/user /etc 2>/dev/null' | grep . && echo FAIL: identity or endpoint leak
docker run --rm --entrypoint /bin/sh n8n-sandbox:latest -c \
  'nix config show | grep -E "^(accept-flake-config|substituters|trusted-public-keys)"'
```

Run the container with the runner's flags (`--user 1000:1000 --cap-drop ALL
--security-opt no-new-privileges`) and repeat the functional tests already
done on 2026-09-25:

- daemon healthy
- `nix run nixpkgs#hello`
- the n8n workflow SDK imports
- `pip install` / `npm i -g` succeed
- `git commit` works with the bot identity and no signing prompt

Exit: all checks pass, and the image digest is recorded.
Teardown: none needed.

## Stage 1: lab deployment and orchestrator-mediated Git

Disposable resources:

- A scratch **private** repository, e.g. `whexy/agent-sandbox-scratch`, with
  dummy content.
- A throwaway GitHub App `whexy-agent-poc`:
  - Contents RW, Pull requests RW, Metadata R, no Workflows
  - installed only on the scratch repo
  - private key generated for the PoC, kept in a disposable agenix file
    encrypted to a PoC-only recipient
- Rulesets on the scratch repo:
  - restrict updates to the default branch (no bypass)
  - require a PR
  - require signed commits
  - push rule "Restrict file paths" on `.github/**`
- A lab namespace with the chart:
  - `runner.isolation: sysbox`
  - `networkPolicy.enabled: true`
  - the image pinned by digest
  - API reachable only through the tailnet or `kubectl port-forward`

Flow ([04](04-git-credentials.md#stages-12-the-orchestrator-commits-and-the-sandbox-holds-no-credentials)):
n8n asks the broker (a small script or n8n Code node at this stage) for a
token scoped to the scratch repo. The broker uploads the tree, the agent edits
and tests, and the broker commits via `createCommitOnBranch` to `agent/poc-1`
and opens a draft PR.

Exit checks:

- The PR's commit shows **Verified**, authored by the app bot.
- Direct push to the default branch with the installation token is rejected.
- A commit touching `.github/workflows/x.yml` is rejected.
- `DELETE /installation/token` makes the token fail within a minute.
- No token string appears in n8n execution data, API logs, runner logs or
  daemon logs (grep for the token prefix).

Teardown: uninstall the app, delete its private key, archive the scratch
repo.

## Stage 2: red-team the defaults

Run each probe as an exec in a `public` sandbox and in a `none` sandbox:

| Probe                  | Command sketch                                                                 | Expected                                                                  |
| ---------------------- | ------------------------------------------------------------------------------ | ------------------------------------------------------------------------- |
| RFC1918 / cluster      | `curl -m3 http://10.96.0.1`, a pod IP, a node LAN IP                           | Blocked                                                                   |
| Tailnet                | `curl -m3 http://100.x.y.z` (a real tailnet host)                              | Blocked                                                                   |
| Metadata               | `curl -m3 http://169.254.169.254`                                              | Blocked                                                                   |
| Cluster DNS            | `getent hosts kubernetes.default.svc.cluster.local`                            | Record the result. [I] predicts it resolves under `public`                |
| DNS tunnel             | Resolve `<random>.<owned test domain>` and check the authoritative server logs | Record. Mitigate with Cilium DNS L7 if it arrives                         |
| Public cluster ingress | `curl` the Sandbox API's own public hostname or NodePort                       | Record. Must require auth                                                 |
| Runner                 | `curl -k https://<runner-ip>:8080/healthz` from the sandbox                    | Blocked (INPUT drop)                                                      |
| Other sandboxes        | `curl http://<other-sandbox-ip>:8081/healthz`                                  | Blocked                                                                   |
| Privileges             | `capsh --print`, `unshare -Ur true`, `find / -perm -4000`                      | No caps. Record the `unshare` result (user-namespace surface). No setuid  |
| Files API scope        | read `/proc/1/environ` and `/etc/passwd` via the files API                     | Readable. Document; no secrets present                                    |
| Resource limits        | fork bomb, `fallocate -l 20G`, 50 MB download via the files API                | Contained by pids and disk quota; note the memory spike from the download |
| Nix trust              | `nix run` a local flake with `nixConfig.extra-substituters`                    | Rejected (`accept-flake-config = false`)                                  |

Exit: every "Blocked" holds, and "Record" items are documented with a
decision.

## Stage 3: egress proxy and Git proxy

Build:

- The runner patch: a `proxy` egress mode that allows one IP:port and drops
  everything else. Keep it as a fork branch; propose it upstream.
- A Smokescreen or Squid deployment with a per-session ACL.
- A minimal Git proxy that enforces repo, ref and path policy and injects the
  installation token.
- The broker issues opaque session tokens (random, 1 h) and maps them to
  (repo, branch, allowed hosts).

Disposable credentials: the same PoC app, and session tokens generated per
run.

Exit checks:

- `git push origin agent/poc-2` works through the proxy.
- A push to any other ref, or touching `.github/**`, fails.
- `curl https://example.com` fails. Allowlisted registries work.
- Revoking a session makes the next request fail within 60 s.
- An env dump from the sandbox shows only the session token, never the
  installation token.

Teardown: revoke all sessions, uninstall the app, remove the proxy
deployment.

## Stage 4: one private service through Tailscale

Only after reviewing the tailnet policy change:

- The Tailscale operator, authenticated by workload identity federation.
- One ProxyGroup (`type: egress`) tagged `tag:k8s-sbx-egress`, with one grant
  to a disposable test service (e.g. a static HTTP server tagged
  `tag:sbx-test`, port 443 only).
- Tailnet lock with pre-signed keys, if lock is in use.
- The proxy ACL gains that service. NetworkPolicy allows only the proxy to
  reach the ProxyGroup Service.

Exit checks:

- The sandbox reaches the test service through the proxy, and nothing else on
  the tailnet.
- The ProxyGroup cannot be reached from the tailnet (no inbound grants).
- The `funnel` attribute is absent.

Teardown: delete the grant, ProxyGroup and test node.

## What must be decided before stage 1

1. Rotate and authenticate the `personal` MCP endpoint (a production change;
   see the [README](README.md#findings-that-need-action-before-anything-else)).
2. Confirm the cluster facts this repository cannot show:
   - Kubernetes version (Sysbox supports 1.32–1.35)
   - CNI (Cilium or not)
   - node OS and kernel
   - whether a node can be dedicated and tainted
   - which storage classes exist
3. Decide where the broker runs: an n8n Code node (simplest), a NixOS service
   on a host, or a cluster Deployment. The GitHub App key's recipient follows
   from that choice.
4. Decide whether CLI agents (claude, codex) run inside the sandbox at all.
   If not, the agent profile can drop the harness packages entirely, and model
   keys never approach the sandbox.
