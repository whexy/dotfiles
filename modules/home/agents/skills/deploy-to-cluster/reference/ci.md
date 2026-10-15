# Woodpecker CI

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
- `ci_cache_access_key`, `ci_cache_secret_key` and `nix_cache_signing_key`:
  the shared build cache (below).

Never use a secret in a `pull_request` step, except the three build-cache
secrets. They let a step write the cache, which is acceptable because only
Wenxuan's own code runs in this CI.

## Build cache

Use the shared cache ([whexy/ci-cache](https://github.com/whexy/ci-cache))
for downloads and builds:

- A Nix step runs on `ghcr.io/whexy/nix-ci:<version>` instead of `nixos/nix`,
  with the cache's secrets. The image enables flakes, so it needs no
  `NIX_CONFIG`:

  ```yaml
  image: ghcr.io/whexy/nix-ci:0.1.0-alpha.3
  environment:
    AWS_ACCESS_KEY_ID:
      from_secret: ci_cache_access_key
    AWS_SECRET_ACCESS_KEY:
      from_secret: ci_cache_secret_key
    NIX_CACHE_SIGNING_KEY:
      from_secret: nix_cache_signing_key
  ```

- For other toolchains, restore and save the cache directory (`.npm`, a cargo
  home) with the `ghcr.io/whexy/ci-cache` plugin; its README has the step
  pair. Add the pair only when a step spends more than about 8 s downloading
  or rebuilding.

nix-ci builds without the Nix sandbox, which step pods cannot host, so a check
that reaches the network passes in CI; only a sandboxed build on a laptop
catches it.

### Docker images

Build outside Docker
([ci-cache README](https://github.com/whexy/ci-cache#docker-images)):

1. Build in a normal step, with the cache above, and copy what the image needs
   into a workspace directory. The template's `build` step uses `.image/`.
2. Point the image step's `context:` at that directory, and have the
   Dockerfile only `COPY` from it.
3. Give the repo a script or flake app that runs the build and then
   `docker build`, for local builds.

whexy/t3code's `.woodpecker/self-hosted-build.yaml` builds two images this
way.

## Pipeline shape (`templates/app/.woodpecker.yaml`)

| Event                        | Steps                                                                                              |
| ---------------------------- | -------------------------------------------------------------------------------------------------- |
| `pull_request`, `manual`     | `validate`, then `test-release`. This is the only validation gate.                                 |
| `push` to the default branch | `prepare-release`: release-please. Manual runs on the default branch also run it, after the tests. |
| `tag` `refs/tags/v*`         | `verify-tag` → `build` → `publish` → `publish-release`                                             |
| any other push               | nothing; open a PR or start a manual run                                                           |

- Fill `validate` with the project's toolchain image and commands: install
  from the lockfile, lint and typecheck, test, build, and smoke-test if
  possible.
- Fill `build` with the same install and build, and copy what the image needs
  into `.image/` ([Docker images](#docker-images)).
- Steps have no `depends_on`, so they run serially, and `when` filters which
  ones run.
- `verify-tag` fails unless the tag is `v` plus the version in
  `.release-please-manifest.json`.
- `publish` pushes only the exact version, `ghcr.io/${CI_REPO}:<version>`.
  Never push `latest`, branch or floating tags.

## Cluster requirements (already in the template)

- The clone and every step are pinned to `kubernetes.io/arch: amd64`. The
  `local-path` workspace binds to the clone Pod's node, and later steps follow
  it.
- Steps default to 1 vCPU / 2 GiB and are OOMKilled above that. Heavy steps
  declare `backend_options.kubernetes.resources`; the image build requests 2
  CPU / 4 GiB with limits of 4 CPU / 6 GiB.
- Images are built with `woodpeckerci/plugin-docker-buildx`, the only plugin
  allowed to run privileged. It is configured with:
  - `context: .image`, the `build` step's output;
  - `mtu: 1230`, because the pod network runs over Tailscale;
  - `storage_path: /woodpecker/docker`, so layers live on the workspace
    volume;
  - `provenance: false`;
  - explicit OCI labels.

Lint before pushing:

```sh
woodpecker-cli lint --strict --plugins-privileged woodpeckerci/plugin-docker-buildx .woodpecker.yaml
```

## Gotchas

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
