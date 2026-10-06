# Deploy to the cluster

## Find clusters-work and update it

clusters-work is usually checked out next to the project (`../clusters-work`),
but its location varies. Look there first, then search nearby, for example
with `find ~ -maxdepth 3 -type d -name clusters-work`. Confirm its `origin` is
`whexy/clusters-work`. Clone it next to the project only if no checkout
exists.

Before changing anything, run `git pull` on `master`. The image updater
commits there continually.

## The cluster

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

## Workload

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

## Image auto-updater

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

## Ingress: tailnet only by default

`tailscale-ingress.yaml` serves `https://<name>.at-basking.ts.net` through
the shared `ingress-proxies` ProxyGroup. The app still authenticates its own
users.

A public host is added only when Wenxuan asks; see [public-host.md](public-host.md).

## Secrets

If the app needs secrets, follow [secrets.md](secrets.md).

## Validate, ship, document

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
