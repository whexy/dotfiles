# Container image

The project needs a `Dockerfile` at its root:

- Only copy in what CI already built. The pipeline's `build` step writes it to
  `.image/`, which is the image's build context; the Dockerfile runs no
  install or build ([Docker images](ci.md#docker-images)).
- Give the repo a script or flake app that runs the same build and then
  `docker build`, for local builds.
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

A repo under the [inline-cache exception](ci.md#docker-images) builds inside
Docker with the repo as its context. Its `.dockerignore` must exclude `.git`,
`.woodpecker*`, `release/`, tests, docs and local data.

CI builds linux/amd64 only, because the cluster's workers are amd64. CI adds
the OCI labels, including `org.opencontainers.image.source`, which links the
GHCR package to the repository. Keep the package private. The cluster pulls
private `ghcr.io/whexy/*` images with a node-level credential, so no pull
secret is needed.
