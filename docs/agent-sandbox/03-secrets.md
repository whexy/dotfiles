# 3. Secrets

Working assumption, from the brief: **the agent can read every secret or key
that any of its commands can reach**, whether it sits in the environment, a
file, a socket, or process memory. A secret delivered to the sandbox is a
secret delivered to the agent, and to any prompt-injected content the agent
has read.

## The existing system is agenix

[V] Evidence:

- `agenix` is a flake input (`flake.nix:66-69`). It is wired into NixOS
  (`lib/default.nix:93`), Darwin (`lib/default.nix:143`) and every Home
  Manager home (`modules/home/all.nix:7`).
- There is no sops-nix input or module.
- `secrets/secrets.nix` is the CLI recipient file, not imported by any Nix
  config (`:1`). It has **one recipient** (`:3-4`), and all 15 `.age` files
  are encrypted to it (`:7-21`).
- Home Manager decrypts to `${XDG_RUNTIME_DIR}/agenix/<name>` through an
  `agenix` user service. Consumers read the path at run time
  (`modules/home/agents/default.nix:242-260`).
- The identity is a hand-copied `~/.config/agenix/key.txt`
  (`modules/home/caps/dev-lite.nix:41-42`). The system-level monitoring secret
  reuses the same user file (`modules/hosts/monitoring/nixos.nix:21`).

Other credential paths in use:

- 1Password: SSH agent and signing (`modules/home/ssh/default.nix:47-64`,
  `modules/home/vcs/git-signing.nix`).
- The gh keyring token, used for Nix fetches (`packages/nix-gh-token`).
- A GitHub App token minter used by CI (`packages/github-app-token`,
  `.woodpecker.yml:21-49`).
- A shared Cloudflare Access service token for the AI proxy, NAS and panel
  (`agents/proxy.nix:13-29`, `rclone/default.nix:343-357`).

**Implication for agents.** On dev hosts, agents already run as the user who
can read `key.txt` and every decrypted secret. The sandbox work is the first
place where that can be fixed, so the sandbox must never receive the age
identity.

## Runtime delivery options

Constraint from [01](01-n8n-sandbox-service.md#what-the-service-offers-for-secrets):
the service lets a client pass secrets only through per-exec `env` or
files. Sandbox pods are created by the runner, so Kubernetes pod-spec
mechanisms (env from Secret, volumes, sidecars, injectors) cannot reach an
individual sandbox. They can still configure the trusted components: the
broker, the proxy and n8n.

| Option                                                           | Complexity  | If the agent is adversarial                                                                                                                      | Revocation                                                                                                                                   | Fits this service                                             | Verdict                                                            |
| ---------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------ |
| Kubernetes Secret as env                                         | Low         | Agent reads it. Env "remains in memory and logs" [D](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)                       | Pod restart                                                                                                                                  | Not per sandbox                                               | For trusted components only                                        |
| Kubernetes Secret as read-only projected volume (tmpfs)          | Low         | Agent reads the file                                                                                                                             | Kubelet refreshes the file; the credential stays valid                                                                                       | No volume API                                                 | For trusted components only (preferred over env)                   |
| Host-side decryption (agenix/sops-nix on the node) plus hostPath | Medium      | Plaintext on the node, visible to any pod with the hostPath                                                                                      | Redeploy                                                                                                                                     | No volume API; breaks node isolation                          | Reject                                                             |
| Sandbox-side decryption with an injected age key                 | Low         | **Worst.** The key decrypts every file encrypted to it, now and in future. age files are not authenticated [D](https://github.com/ryantm/agenix) | Rotate every secret                                                                                                                          | Via env                                                       | **Reject**                                                         |
| Per-exec env with a short-lived token                            | Low         | Agent reads and can exfiltrate it until expiry                                                                                                   | TTL, or revoke at the issuer                                                                                                                 | Yes                                                           | Acceptable for 1 h, one-repo tokens only                           |
| External Secrets Operator, sops-secrets-operator, Flux+sops      | Medium      | Ends up as a Kubernetes Secret                                                                                                                   | Refresh interval                                                                                                                             | For trusted components                                        | Good way to feed the broker, if the cluster has GitOps             |
| Secrets Store CSI driver                                         | Medium–High | Mounted file readable                                                                                                                            | Rotation alpha [D](https://secrets-store-csi-driver.sigs.k8s.io/)                                                                            | For trusted components                                        | Optional                                                           |
| Vault/OpenBao (dynamic secrets, response wrapping, short leases) | High        | Agent gets what it unwraps; wrapping detects interception [D](https://developer.hashicorp.com/vault/docs/concepts/response-wrapping)             | Immediate lease revocation                                                                                                                   | Vault must be reachable, but RFC1918 is blocked               | Over-engineered at homelab scale; revisit if secrets multiply      |
| SPIFFE/SPIRE, projected SA token plus OIDC federation            | High        | Short-lived identity the agent can use while it lasts                                                                                            | Minutes; SA tokens outlive their pod for OIDC verifiers [D](https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/) | No socket or token inside the sandbox                         | Use for the broker's own identity (e.g. octo-sts), not the sandbox |
| **Secret broker** (mints scoped, short-lived credentials)        | Medium      | Agent never sees long-lived material                                                                                                             | Instant at the broker; TTL at the issuer                                                                                                     | Broker runs outside                                           | **Adopt**                                                          |
| **Credential-injecting egress proxy**                            | Medium      | Agent sees an opaque session token. It can _use_ the proxy within policy (confused deputy), but not take the credential elsewhere                | Instant (session revoke)                                                                                                                     | Needs a reachable proxy address ([05](05-storage-network.md)) | **Adopt in stage 3**                                               |

Precedents for the proxy pattern:

- **Anthropic, Claude Code on the web**: "Sensitive credentials (such as git
  credentials or signing keys) are never inside the sandbox"; a Git proxy
  checks the scoped credential and the push target, then attaches the real
  token [D](https://www.anthropic.com/engineering/claude-code-sandboxing).
- **Claude Code sandbox `mask` mode**: the command sees a sentinel value that
  the proxy swaps for the real one on allowed hosts
  [D](https://code.claude.com/docs/en/sandboxing).
- **Fly.io tokenizer**: sealed secrets with host restrictions
  [D](https://github.com/superfly/tokenizer).
- **Infisical Agent Vault**: an `HTTPS_PROXY` with a per-agent session
  credential [D](https://github.com/Infisical/agent-vault).
- **kubernetes-sigs/agent-sandbox #1045**: proposes an egress sidecar in place
  of env-injected Secrets
  [D](https://github.com/kubernetes-sigs/agent-sandbox/issues/1045).

## Recommendation

1. **Nothing long-lived in the sandbox.** In stages 0–2 the sandbox holds no
   credential at all. From stage 3 it holds only an opaque, revocable session
   token for the proxy, passed in exec `env` (never in command text, which the
   daemon logs).
2. **Keep agenix for the trusted side, and split recipients.** Add a
   dedicated recipient for the broker (a host SSH key or its own age key), and
   encrypt only broker secrets to it:
   - the GitHub App private key
   - the proxy's upstream credentials
   - n8n's Sandbox tenant key

   The master `key` should stop being the recipient for new agent-related
   secrets. Migrating to sops-nix is optional: it adds MACs and KMS backends,
   but it does not change the sandbox design.

3. **Getting broker secrets into Kubernetes** (if the broker runs in the
   cluster):
   - Short term: on a trusted admin host, render a Secret from agenix output
     and pipe it to `kubectl apply`. Never echo it, and never write it to a
     file or the Nix store.
   - Longer term: sops-secrets-operator or ESO if the cluster adopts GitOps.

   Either way, enable etcd encryption at rest and restrict Secret `get`/`list`
   RBAC to the broker's ServiceAccount (`list` implies read
   [D](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)).

4. **Model API credentials.** Default: the agent loop runs in n8n, so the key
   lives in n8n's credential store and never in the sandbox. If CLI agents
   (claude, codex) must run inside the sandbox, give them a per-task virtual
   key with a spend cap and TTL, issued by the AI proxy, or route them through
   the injecting proxy. Whether the current AI proxy (`agents/proxy.nix:13`)
   supports per-key budgets and expiry is **unverified**.
5. **Logs.** n8n saves execution data (by default for failed executions, kept
   14 days [D](https://docs.n8n.io/deploy/host-n8n/configure-n8n/scaling/manage-execution-data.md)).
   Any node that handles a token must have execution-data saving off for that
   node, or have the token masked. Proxy logs record host, bytes and sandbox
   id, never headers or bodies.

## Hard rules (checked in PoC stage 0)

- No plaintext secret or decryption key in the image, the Nix store, Git, or
  build logs. Encrypted `.age` files must not be in the image closure either:
  `nix path-info -r` on the image must contain no `*.age` store path.
- No age identity path configured in the agent profile (`age.identityPaths`
  unset, no `age.secrets`).
- No secret in an exec `command` string.
- Every credential that reaches a sandbox has TTL ≤ 1 h, a single-resource
  scope and a revocation path the broker can trigger.
