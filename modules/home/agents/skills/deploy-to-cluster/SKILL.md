---
name: deploy-to-cluster
description: Set up or change a project's deploy pipeline to Wenxuan's cluster (GitHub repo rules, Woodpecker CI, release-please, GHCR image, ArgoCD manifests in clusters-work). Use when deploying to "the cluster" or changing any of these for a deployed project.
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

Paths under `templates/` and `reference/` are relative to this skill's
directory.

## Steps

For a new deployment, work through every step in order; later steps depend on
earlier ones. To change one part of an existing deployment, read only its
file.

1. [Repository](reference/repository.md): private repo, rebase-only merges,
   branch ruleset.
2. [Container image](reference/image.md): Dockerfile and `.dockerignore`
   requirements.
3. [Woodpecker CI](reference/ci.md): activation, org secrets, pipeline shape,
   cluster limits, debugging failed pipelines.
4. [release-please](reference/release.md): release flow, config settings,
   bootstrapping, going stable.
5. [Image-update webhook](reference/image-webhook.md): GHCR package events to
   argocd-image-updater.
6. [Deploy to the cluster](reference/cluster.md): clusters-work layout,
   workload manifests, image auto-updater, tailnet ingress, docs.
   - [Secrets](reference/secrets.md): agenix to Kubernetes Secret.
   - [Public host](reference/public-host.md): only when Wenxuan asks.
7. [Verify end to end](reference/verify.md), and report anything you could
   not verify as unverified.
