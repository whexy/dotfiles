---
name: deploy-to-cluster
description: Wenxuan's personal deploy pipeline - private GitHub repo, Woodpecker CI with release-please publishing private GHCR images, and an auto-updating ArgoCD workload in clusters-work. Read before deploying a project to "the cluster", or before setting up or changing such a project's repository settings, CI, release flow, image, or cluster manifests.
---

# Deploy pipeline

When asked to deploy something to "cluster", set up this whole pipeline. The
result is:

- a private repo `whexy/<name>` whose default branch only changes through
  rebase-merged PRs that passed CI;
- Woodpecker CI that validates PRs, lets release-please run releases, and
  publishes the private image `ghcr.io/whexy/<name>:<version>` for each
  release;
- a workload in clusters-work that argocd-image-updater moves to every new
  release.

`<name>` is used throughout. The repository, image, Kubernetes namespace,
Deployment and ArgoCD Application all share it.

This skill's `templates/` directory holds tested files. Copy them and fill in
the `<…>` placeholders; do not rewrite them from memory.

| Template                        | Destination                                                                                                     |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| `templates/app/`                | Project root: `.woodpecker.yaml`, `release-please-config.json`, `.release-please-manifest.json`, and `release/` |
| `templates/github/ruleset.json` | The repository's branch ruleset                                                                                 |
| `templates/cluster/gitops/`     | clusters-work's `gitops/`, renaming `NAME` to `<name>`                                                          |

Work in this order. Later steps depend on earlier ones.

## 1. Repository

If the project is not on GitHub yet, create it private and push the current
default branch. The ruleset comes later, because it blocks direct pushes.

```sh
gh repo create whexy/<name> --private --source . --push
gh repo edit whexy/<name> \
  --enable-rebase-merge --enable-squash-merge=false --enable-merge-commit=false \
  --delete-branch-on-merge --enable-auto-merge --enable-wiki=false
```

PRs merge by rebase only. Every commit on a PR branch lands on the default
branch, and release-please reads each one, so every commit title must follow
`type(scope): description`.

Once Woodpecker has activated the repo (step 3), add the ruleset:

```sh
gh api repos/whexy/<name>/rulesets --method POST --input <this skill's directory>/templates/github/ruleset.json
```

The ruleset makes PRs the only way in. It allows rebase merges only and
requires `ci/woodpecker/pr/woodpecker` on a branch that is up to date with
the base. Woodpecker names that check after the event and the workflow file,
so keep the pipeline in one `.woodpecker.yaml`.

The strict up-to-date check is what makes the CI design sound. Every commit
on the default branch has exactly the tree its PR pipeline validated, release
PRs included, so pushes and tags never re-validate. Never relax it without
restoring validation on push and tag events.

## 2. Container image

The project needs a `Dockerfile` at its root:

- Use a multi-stage build so the runtime image holds no build tools or tests.
- Run as UID/GID 1000 and work on a read-only root filesystem with a writable
  `/tmp`. Keep all persistent state under `/data`.
- Serve a health endpoint for probes; the templates use `GET /healthz`.
- Accept the build arguments CI passes. Annotate the version so release-please
  keeps it current:

  ```dockerfile
  # x-release-please-start-version
  ARG VERSION=0.1.0-alpha.1
  # x-release-please-end
  ARG SOURCE_REVISION=unknown
  ```

`.dockerignore` must exclude `.git`, `.woodpecker*`, `release/`, tests, docs
and local data.

CI builds linux/amd64 only, because the cluster's workers are amd64. CI adds
the OCI labels, including `org.opencontainers.image.source`, which links the
GHCR package to the repository. Keep the package private. The cluster pulls
private `ghcr.io/whexy/*` images with a node-level credential, so no pull
secret is needed.

## 3. Woodpecker CI

Woodpecker runs at <https://make.clusters.work> on the cluster's Kubernetes
backend. There are no GitHub Actions. Activating a repo also installs its
GitHub webhook:

```sh
woodpecker-cli repo add "$(gh api repos/whexy/<name> --jq .id)"
```

If `woodpecker-cli` is not logged in to that server, ask Wenxuan.

Secrets are organization secrets on `whexy` and apply to every repo. Do not
create repo secrets.

- `ghcr_token`: used to push images and look up their digests.
- `github_app_id`, `github_app_installation_id` and `github_app_private_key`:
  the `whexy-bot` GitHub App that release-please acts as. The App is installed
  on every `whexy/*` repository, so new repos need no GitHub-side setup.

Never use a secret in a `pull_request` step.

### Pipeline shape (`templates/app/.woodpecker.yaml`)

| Event                        | Steps                                                                                              |
| ---------------------------- | -------------------------------------------------------------------------------------------------- |
| `pull_request`, `manual`     | `validate`, then `test-release`. This is the only validation gate.                                 |
| `push` to the default branch | `prepare-release`: release-please. Manual runs on the default branch also run it, after the tests. |
| `tag` `refs/tags/v*`         | `verify-tag` → `publish` → `publish-release`                                                       |
| any other push               | nothing; open a PR or start a manual run                                                           |

- Fill `validate` with the project's toolchain image and commands: install
  from the lockfile, lint and typecheck, test, build, and smoke-test if
  possible.
- Steps have no `depends_on`, so they run serially, and `when` filters which
  ones run.
- `verify-tag` fails unless the tag is `v` plus the version in
  `.release-please-manifest.json`.
- `publish` pushes only the exact version, `ghcr.io/${CI_REPO}:<version>`.
  Never push `latest`, branch or floating tags.

### Cluster requirements (already in the template)

- The clone and every step are pinned to `kubernetes.io/arch: amd64`. The
  `local-path` workspace binds to the clone Pod's node, and later steps follow
  it.
- Steps default to 1 vCPU / 2 GiB and are OOMKilled above that. Heavy steps
  declare `backend_options.kubernetes.resources`; the image build requests 2
  CPU / 4 GiB with limits of 4 CPU / 6 GiB.
- Images are built with `woodpeckerci/plugin-docker-buildx`, the only plugin
  allowed to run privileged. It is configured with:
  - `mtu: 1230`, because the pod network runs over Tailscale;
  - `storage_path: /woodpecker/docker`, so layers live on the workspace
    volume;
  - `provenance: false`;
  - explicit OCI labels.

Lint before pushing:

```sh
woodpecker-cli lint --strict --plugins-privileged woodpeckerci/plugin-docker-buildx .woodpecker.yaml
```

### Gotchas

- **Build from `tag`, never `release`.** Woodpecker starts pipelines only for
  GitHub's `released` action, which a pre-release never sends, so every
  `0.1.0-alpha.<n>` release would silently skip a `when: event: release`
  step. The webhook `woodpecker-cli repo add` installs does not subscribe to
  release events either.
- **`nixos/nix` has no coreutils extras.** A step on that image has no `sed`
  or `grep`; use `nix eval`, shell builtins, or a different image.
- **Reading a failed pipeline:** `woodpecker-cli pipeline ls whexy/<name>`,
  then `woodpecker-cli pipeline log show whexy/<name> <number> <step>`. Read
  the log before rerunning anything.

## 4. release-please

release-please runs inside Woodpecker as `whexy-bot`. The tooling is
language-agnostic and lives in `release/` with its own pinned dependencies.
Generate its lockfile once with `npm install --prefix release` and commit
`release/package-lock.json`. Keep `release/` out of the project's own
packaging, linters and typecheck.

- `github-app.mjs` mints an App installation token scoped to `CI_REPO_NAME`.
- `release-please.mjs` opens or updates the release PR and creates releases.
- `publish-release.mjs` finalizes the draft release.
- `release.test.mjs` covers all three plus the configuration, and runs on
  every PR.

The flow:

1. Each push to the default branch opens or updates one release PR. Its PR
   pipeline validates the exact tree that will be published.
2. Merging the release PR makes the next push create the `v<version>` tag and
   a draft GitHub release.
3. The tag pipeline publishes the image. `publish-release` then writes notes
   with the image's digest and publishes the release.
4. A failed tag pipeline leaves the release as a draft. Fix the cause and
   rerun the tag pipeline.

Never create tags or releases by hand.

Settings in `release-please-config.json`:

- **Tags:** `include-component-in-tag: false`, so git tags are `v<version>`
  and image tags are the same version without the `v`.
- **Versioning:** `versioning: prerelease`, `prerelease-type: alpha`,
  `prerelease: true`, `bump-minor-pre-major` and
  `bump-patch-for-minor-pre-major`. New projects stay on the
  `0.1.0-alpha.<n>` line until Wenxuan decides to go stable.
- **Draft release and forced tag:** `draft: true` with `force-tag-creation:
true`. The tag exists at once and triggers the build, while the release
  stays a draft until its image exists. The tag event can arrive before the
  draft does, which is why `publish-release` retries.
- **Changelog:** `changelog-type: github`, so notes credit PRs and authors.
- **Release type:** set `release-type` to the language's type (`node`,
  `python`, `rust`, `go`), or `simple`.
- **Version files:** `extra-files` lists every other file that ships the
  version, starting with `Dockerfile`. Mark each version with a trailing
  `x-release-please-version` comment, or a `x-release-please-start-version` …
  `x-release-please-end` block. The release test fails if any listed file is
  not updated.
- **Starting point:**
  - `bootstrap-sha` is the full 40-character SHA of the default-branch HEAD
    before release-please was added. A short SHA is silently ignored.
  - `.release-please-manifest.json` starts as `{}`, and `initial-version`
    names the first release. Never seed the manifest with a placeholder
    version: GitHub changelog generation fails on a previous tag that does
    not exist.

The manifest is CI's version source. After the first release, release-please
owns it, so never edit it by hand.

Before relying on the setup, preview it against the real history (read-only):

```sh
npm ci --prefix release
CI_REPO=whexy/<name> GITHUB_TOKEN="$(gh auth token)" node release/release-please.mjs --dry-run
```

The first push after the bootstrap commit should open the `initial-version`
release PR. If it does not, land a commit whose body contains
`Release-As: 0.1.0-alpha.1`.

### Going stable (only when Wenxuan decides)

1. Set `versioning: default`, `prerelease: false` and `release-as: <x.y.z>`
   in the package config.
2. Merge the resulting release PR, then remove `release-as`.
3. In the same window, widen the cluster's image-updater constraint and
   `allow-tags` to stable versions. The alpha filter rejects stable tags.

Stable releases become GitHub's Latest release; container tags still never
float.

## 5. Image-update webhook

A repository webhook makes argocd-image-updater check as soon as a package is
published; its 30-minute poll is only the fallback. User-owned packages send
`package` events to repository webhooks only, and only for packages linked to
that repository through the `source` label.

```sh
secret=$(cd <clusters-work>/secrets && agenix -d image-updater-webhook.age)
gh api repos/whexy/<name>/hooks --method POST --silent \
  -f name=web -F active=true -f 'events[]=package' \
  -f 'config[url]=https://image-updater.clusters.work/webhook?type=ghcr.io' \
  -f 'config[content_type]=json' -f "config[secret]=$secret"
unset secret
```

Decrypting needs the admin identity. If agenix cannot decrypt on this
machine, ask Wenxuan. Never print the secret.

## 6. Deploy to cluster

### Find clusters-work and update it

clusters-work is usually checked out next to the project (`../clusters-work`),
but its location varies. Look there first, then search nearby, for example
with `find ~ -maxdepth 3 -type d -name clusters-work`. Confirm its `origin` is
`whexy/clusters-work`. Clone it next to the project only if no checkout
exists.

Before changing anything, run `git pull` on `master`. The image updater
commits there continually.

### The cluster

- **Nodes:** k3s, with all nodes joined over Tailscale:
  - an arm64 control-plane VM on AWS, `k8s-aws`, which is also the init node
    that turns agenix secrets into Kubernetes Secrets;
  - amd64 workers at home and on Incus;
  - a tainted node in Hangzhou.
- **Layers:**
  - `nix/` holds the NixOS host configs (blueprint), deployed with
    `just deploy-<host>`.
  - `gitops/` holds the workloads, which ArgoCD syncs from `master`
    (app-of-apps, Kustomize, automated prune and selfHeal). A push to
    `master` deploys.
- **Tools:** work inside its dev shell (`nix develop` or direnv), which
  provides `just`, `kubectl`, `kustomize` and `agenix`.
- **Repo rules:** follow its `AGENTS.md`. It routes to topic docs that record
  constraints for each subsystem.

### Workload

Copy `templates/cluster/gitops/` and fill in `<name>`, `<port>`, `<version>`
and the env.

- **Kustomize root:** `gitops/apps/<name>/` is one. Its `kustomization.yaml`
  has only a `resources:` list naming every manifest; a file it doesn't list
  is never deployed. Each manifest declares `namespace: <name>` itself.
- **Deployment:** the template is the hardened default, so keep its pieces:
  - amd64 `nodeSelector`;
  - UID/GID 1000;
  - read-only root filesystem, dropped capabilities and `RuntimeDefault`
    seccomp;
  - no service-account token;
  - probes;
  - requests and limits;
  - an `emptyDir` at `/tmp`.
- **Image tag:** the image is pinned by tag through the kustomization's
  `images:` entry. Set `newTag` to a version that is already published.
- **State:** a `ceph-block` RWO claim at `/data` with one replica and
  `Recreate`, because two Pods must never write the same data. For a
  stateless app, drop `pvc.yaml` and the `data` volume. Ceph replication is
  not a backup, so write down the backup and restore story.
- **Scheduling:** workloads are Tier B by omission. Use Tier A only for
  infrastructure that other workloads depend on.
- **Application:** add `gitops/argocd-apps/<name>.yaml` and list it in
  `gitops/argocd-apps/kustomization.yaml`.
- **In-cluster dependencies** may admit clients by NetworkPolicy or by
  per-client key. Extend them in the dependency's own app.

### Image auto-updater

The Application template enrolls the image:

```yaml
argocd-image-updater.argoproj.io/image-list: <name>=ghcr.io/whexy/<name>:>=0.1.0-alpha.1 <0.2.0-0
argocd-image-updater.argoproj.io/<name>.update-strategy: semver
argocd-image-updater.argoproj.io/<name>.allow-tags: regexp:^0\.1\.[0-9]+-alpha\.[0-9]+$
argocd-image-updater.argoproj.io/write-back-method: git
argocd-image-updater.argoproj.io/write-back-target: kustomization
argocd-image-updater.argoproj.io/git-branch: master
```

- The image name must be identical in the annotation, the kustomization's
  `images[].name` and the Deployment. Kustomize matches names literally.
- Every comparator needs a prerelease suffix to admit alphas.
- `allow-tags` keeps floating and other unwanted tags out even if the
  constraint is later widened.
- The updater commits `build: automatic update of <name>` to `master`, and
  ArgoCD rolls the Deployment.
- To check now instead of waiting for the poll, run
  `just image-update --dry-run`.

### Secrets

Plaintext never enters git or command output.

1. Register `"<name>.age".publicKeys = initOnly;` in `secrets/secrets.nix`.
   Workload secrets are readable only by the admin and `k8s-aws`.
2. Encrypt from stdin, because agenix without a TTY ignores `$EDITOR`.
   Generate app tokens with `openssl rand -hex 32`, and ask Wenxuan for values
   only they hold.

   ```sh
   printf 'APP_TOKEN=%s\n' "$value" | (cd secrets && agenix -e <name>.age)
   ```

3. Materialize the file as a Kubernetes Secret on the init node. In
   `nix/modules/nixos/k3s-server.nix`, add an option (camelCase for
   hyphenated names) and a `k8sSecrets` entry next to the existing ones:

   ```nix
   <name>.enable = lib.mkOption {
     type = lib.types.bool;
     default = false;
     description = ''
       Create the <name> Secret from agenix. Effective only on the add-on (init) node.
     '';
   };

   # in the k8sSecrets attribute set:
   <name> = lib.mkIf (cfg.deployAddons && cfg.<name>.enable) {
     namespace = "<name>";
     secretName = "<name>";
     ageFile = ../../../secrets/<name>.age;
     data.parseKeyValue = [ "APP_TOKEN" ];
   };
   ```

   Then set `<name>.enable = true;` in the `my.k3s` block of
   `nix/hosts/k8s-aws/configuration.nix`.

4. Run `just deploy-aws` before ArgoCD first syncs the workload. Pods read
   Secrets at start, so roll the Deployment after any rotation.

### Ingress: tailnet only by default

`tailscale-ingress.yaml` serves `https://<name>.at-basking.ts.net` through
the shared `ingress-proxies` ProxyGroup. The app still authenticates its own
users.

### Public host: only when Wenxuan asks

- **Routing:** add an `ingressClassName: nginx` Ingress with
  `host: <name>.clusters.work` and no TLS block. Cloudflare terminates TLS,
  and the `*.clusters.work` tunnel route already forwards to ingress-nginx.
- **Authentication:** a public host is reachable from the whole internet.
  Either the app authenticates every route itself, or Wenxuan puts a
  Cloudflare Access application in front of it. Access lives in the Zero
  Trust dashboard, not in git, and it blocks webhooks and machine clients.
- **Paths:** route only the paths that must be public.
- **Long-lived responses:** streaming or long-lived responses need
  `nginx.ingress.kubernetes.io/proxy-buffering: "off"` plus raised
  `proxy-read-timeout` and `proxy-send-timeout`. Large uploads need
  `proxy-body-size`; Cloudflare's free plan caps request bodies at 100 MB.

### Validate, ship, document

- Run `just validate`, and `just render gitops/apps/<name>` to see exactly what
  ArgoCD applies.
- Commit in the clusters-work style (`gitops(<name>): …`, `secrets: …`,
  `k3s: …`), push to `master`, then run `just deploy-aws` for new secrets.
- In the same change, document the app as clusters-work requires:
  - `docs/<name>.md`, covering access, dependencies, secrets, state and
    backup, and verification;
  - a routing row in `docs/README.md`;
  - rows in the managed-Applications table (`docs/gitops.md`), the enrolled
    images table (`docs/image-updates.md`) and the secrets table
    (`docs/secrets.md`).

## 7. Verify end to end

- **App repo:** a PR shows the required green check, and merging it opens or
  updates the release PR. Merging the release PR produces a tag pipeline that
  publishes the image, then the release with its digest.
- **GitHub:** the GHCR package is private and linked to the repository, and
  the package webhook's latest delivery returned 2xx.
- **Cluster:**
  - ArgoCD shows the Application Synced and Healthy;
  - `kubectl -n <name> rollout status deployment/<name>` succeeds;
  - the health endpoint and ingress respond;
  - one real end-to-end use of the app works.
- **Updates:** the next release reaches the cluster through an image-updater
  commit, with no manual tag bump.
- **Stateful apps:** restart the Deployment and confirm the state survives.

Report anything you could not verify as unverified. Do not claim it works.
