# 1. n8n Sandbox Service: verified behaviour

Source: <https://github.com/n8n-io/n8n-sandbox-service>. Citations are
`path:line` at `81bf9b0` (v1.4.0), the revision this repository pins as the
`n8n-sandbox-service` flake input. v1.5.0 (`14393cf`) adds only provisioner
API keys (`SANDBOX_API_PROVISIONER_KEYS`: tenant create and delete only) and
more error-log context.

## Architecture and trust boundaries

Three tiers: API → runner → daemon. The API is the only tier that knows about
tenants. [D] `docs/security-model.md:9-19`: "Everything trusts the layer above
it. Sandboxes trust nothing." A sandbox escape counts as a runner compromise,
and runner credentials are fleet-wide [D] `security-model.md:230-240`.

| Surface        | Port / protocol                                                                                          | Auth                                                                                                                                              |
| -------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Public API     | HTTP :8080. **Plaintext**: `ListenAndServe` [V] `cmd/api/main.go:153`. TLS must be terminated at ingress | `X-Api-Key`. Admin keys compared in constant time; tenant keys SHA-256 hashed [V] `internal/api/middleware_auth.go:56-96`                         |
| API registry   | gRPC :9090                                                                                               | mTLS plus bearer registration token [V] `internal/api/grpc/runner_server.go:29-41`                                                                |
| Runner control | gRPC :9091 (Create, Stop, Delete) [V] `proto/runner/v1/runner.proto:12-16`                               | mTLS `RequireAndVerifyClientCert` [V] `internal/grpctls/server.go:47`. Any certificate signed by the CA is accepted; there is no identity binding |
| Runner proxy   | HTTPS :8080                                                                                              | Peer certificate plus runner key [V] `internal/runner/middleware_auth.go:16-34`. Health, ready and metrics endpoints are unauthenticated          |
| Daemon         | HTTP :8081 inside the sandbox, **no auth** [V] `internal/runner/runtime/docker/runtime.go:576`           | Reachable only from the runner, because iptables drops other sandboxes [V] `netrules/netrules.go:91-111`                                          |

The chart's NetworkPolicy is off by default and covers **ingress only** [V]
`charts/n8n-sandbox-service/templates/networkpolicy.yaml:58-75`. CORS, when
enabled, allows `*` origins [V] `internal/api/middleware_cors.go:12-14`.

## Custom images

- **One image per runner.** The Docker runner reads
  `SANDBOX_RUNNER_DOCKER_SANDBOX_IMAGE` [V]
  `internal/runner/runtime/docker/config.go:75-78`. A create request carries
  only `id`, `ephemeral` and `egress` [V] `internal/api/handlers.go:133-137`.
  Placement goes to the eligible runner with the lowest load, with no image,
  tenant or label affinity [V] `internal/api/registry/memory.go:133-151`.
  Different images or trust tiers therefore need **separate service
  deployments**, not just separate runners behind one API.
- **Pulling.** The runner skips the pull when `docker image inspect` succeeds
  [V] `docker_client.go:291-297`, so a mutable tag is never refreshed. The
  chart's `runner.sandboxImage.pullPolicy` is declared but unused [V]
  `values.yaml:208`, `templates/_helpers.tpl:110-111`. **Pin by digest** (the
  helper renders `repo:tag`, so `tag: "x@sha256:…"` should work [I]).
- **What the image must provide** [V] `runtime.go:652-707`, `internal/daemon/exec.go:26`:
  - the daemon as `CMD` on :8081
  - `/bin/sh`
  - a successful `true` exec for readiness
  - a user with uid 1000 and home `/home/user`

  The image in `packages/sandbox-image` meets all four.

- **Firecracker** flattens the image into an ext4 template and boots the daemon
  as `init`, so the image `ENTRYPOINT` and `ENV` are ignored [V]
  `scripts/firecracker.ee/create-golden-snapshot.sh:134,182`. It is
  Enterprise-licensed for production use [D] `LICENSE_EE.md`.

## Container lifecycle

- **Create args** [V] `internal/runner/runtime/docker/docker_client.go:155-196`:
  - `--hostname sandbox`
  - `--restart unless-stopped`
  - `--user 1000:1000`
  - `--cap-drop ALL`
  - `--security-opt no-new-privileges`
  - IPv6 disabled by sysctl
  - optional `--memory`/`--cpus`/`--pids-limit`/`--storage-opt size=`
  - **no volumes, no command override, no seccomp or AppArmor profile, no
    read-only root filesystem**
- **Idle stop.** After `SANDBOX_API_IDLE_STOP_AFTER` (default 1 h), the idle
  sweeper runs `docker stop`: processes die and the writable layer persists [V]
  `internal/api/ttl.go:267-300`. Activity is recorded when a response starts,
  so a long-running exec can be stopped mid-run [D] `docs/API.md:235`.
- **Idle delete.** After `SANDBOX_API_IDLE_DELETE_AFTER` (default 24 h), for
  stopped sandboxes. `ephemeral` sandboxes are deleted at the idle-stop point
  instead [V] `ttl.go:221-265`.
- **Wake.** Any proxied request wakes a stopped sandbox, except
  `DELETE …/executions/{id}` [V] `internal/runner/proxy.go:39-41,124-160`.
- **Crash recovery.** Docker restarts the container, and the next request gets
  `409 sandbox_restarted` [V] `runtime.go:393-463`.
- **Runner restart deletes every sandbox** [V] `runtime.go:102,613-617,713-724`.
- **Limits are runner-wide.** Defaults are 512 MB, 100% CPU and 256 pids [V]
  `docker/config.go:10-14`. The disk quota defaults to off and needs an
  xfs+prjquota pool [V] `runtime.go:619-630`.
- **Robustness gaps:**
  - Exec `timeout_ms` has no maximum [V] `daemon.go:26,128-131`.
  - The daemon is PID 1 and does not reap zombies [V] (no `Wait4`/subreaper
    in the tree).
  - A single output line over 64 KiB likely stalls the stream reader [I]
    `exec.go:91,104`.
  - `setsid` children survive cancel [I].

## Startup configuration and exec API

- **Environment.** User commands get a **replaced** environment: `HOME`, a
  fixed `PATH`, and the request's `env` map on top [V] `exec.go:26-41`. Image
  `ENV` never reaches commands. The sandbox image handles this by making
  `/usr/local` the Home Manager profile.
- **No create-time hook, environment or labels** [V] `runner.proto:33-36`,
  `docker_client.go:162-163`.
- **Exec.** Commands run via `/bin/sh -c` in their own process group. Output
  is NDJSON with sequence numbers, and `exec_id` allows idempotent resume. Each
  execution has a 16 MiB ring buffer and is kept 10 minutes. The body is capped
  at 1 MiB [V] `internal/daemon/daemon.go:23,133-187`,
  `exec_manager.go:14-15`.
- **The daemon logs every command string at info level** [V] `exec.go:63`.
  The `env` values are not logged.
- **Files API.** Paths resolve to `filepath.Join("/", Clean("/"+p))` [V]
  `internal/daemon/files.go:14-16`: anything uid 1000 can read or write,
  including `/proc/<pid>/environ` of other sandbox processes [I]. Uploads are
  capped at 10 MB. **Downloads are not capped**, and the daemon reads the whole
  file into memory [V] `daemon.go:216`.
- **SDK** (`sdk/src/client.ts:48-157`): sandbox CRUD (`egress` required),
  exec, resume, delete-execution and the file operations. No admin
  operations. After every exec the SDK deletes the execution in the background
  [V] `sdk/src/exec.ts:82`.

## Volumes

There is no volume, bind-mount, PVC, snapshot or export API [V]
`docker_client.go:155-183`. Data moves file by file through the files API.
The only PVCs in the chart are the API's SQLite store and an optional
per-runner inner Docker data root [V]
`templates/api-pvc.yaml`, `runner-statefulset.yaml:218-231`.

## Networking

- **Two bridges** [V] `runtime.go:744-761`, `netrules/netrules.go:158-185`:
  - `public`: allow all except a fixed IPv4 denylist.
  - `none`: drop every forwarded packet, DNS included.
  - Inter-container communication is off on both. Sandboxes cannot reach the
    runner host (INPUT drop).
- **Denylist** [V] `internal/runner/runtime/netpolicy/private_ranges.go:6-15`:
  `10/8, 172.16/12, 192.168/16, 169.254/16, 127/8, 100.64/10, 198.18/15, 240/4`.
  This includes **Tailscale's 100.64/10** and the usual pod and Service CIDRs.
  A `public` sandbox therefore cannot reach tailnet or ClusterIP services.
- "Per-sandbox allowlists are not implemented" [D] `docs/security-model.md:264`.
  The egress mode is fixed at create.
- **DNS.** No `--dns` is passed. On the public bridge, Docker's embedded
  resolver forwards queries from the runner's network namespace, so cluster
  names probably resolve and DNS tunnelling to the internet is probably
  possible [I]. Tested in PoC stage 2.
- **Public IPs are allowed.** Node public IPs, NodePorts and load balancers,
  including the Sandbox API's own ingress, are reachable from `public`
  sandboxes [I].
- **No port exposure** into sandboxes. Only daemon routes are proxied [V]
  `internal/runner/server.go:47-64`.

## Privilege boundaries on Kubernetes

- **Sysbox (default).** `runtimeClassName: sysbox-runc`, `hostUsers: false`,
  node label `sysbox-install=yes` [V] `values.yaml:237-250`,
  `runner-statefulset.yaml:41-46`. Nodes need Sysbox installed by a privileged
  DaemonSet. Kubernetes 1.32–1.35, containerd ≥ 2.0.5 [D]
  `docs/quickstart-k8s.md:11-16,52-64`.
- **Privileged.** Needs `runner.acknowledgePrivileged` and the PSA
  `privileged` level [V] `templates/validation.yaml:37`,
  `runner-statefulset.yaml:51-54`.
- **Sandbox container.** Never privileged [D]
  `security-model.md`. The daemon drops to uid 1000 if started as root [V]
  `internal/daemon/user.go:20-37`. The upstream image strips setuid bits [V]
  `Dockerfile.sandbox:68`, and the Nix image has none.

## What the service offers for secrets

**Nothing.** There is no secret store, no create-time environment and no
mount. A credential can only arrive through the per-exec `env` map or a file
written through the files API. Both are readable by every uid-1000 process in
the sandbox, and files persist across stop/wake [V] (`exec.go:38-41`, the
absence of any secret field in `runner.proto`). This fact drives the
"no secrets in the sandbox" design in [03-secrets.md](03-secrets.md).

## Implications for this design

| Service property                            | Design response                                                                                                                        |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| One image per deployment                    | One service deployment per trust tier, e.g. `sandbox-untrusted` (egress `none`) and `sandbox-deps` (egress `public`)                   |
| RFC1918 and CGNAT blocked                   | Private services are unreachable, which is intended. Access needs a runner "proxy" egress mode ([05](05-storage-network.md))           |
| No volumes                                  | Git is the persistence layer. A cache volume needs a runner patch                                                                      |
| Command strings logged                      | Never put secrets in command text. Pass them through `env` only, and only short-lived tokens                                           |
| Files API unrestricted                      | Assume the orchestrator (and anyone holding the tenant key) can read everything in a sandbox. Keep the tenant key in the control plane |
| Plaintext API, open runner health endpoints | Tailnet-only ingress for the API; enable the chart NetworkPolicy                                                                       |
| Mutable tags never re-pulled                | Pin the sandbox image by digest in Helm values                                                                                         |
