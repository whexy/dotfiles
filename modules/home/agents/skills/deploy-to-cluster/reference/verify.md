# Verify end to end

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
