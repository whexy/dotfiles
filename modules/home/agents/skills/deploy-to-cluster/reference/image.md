# Container image

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
