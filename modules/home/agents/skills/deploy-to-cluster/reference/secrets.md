# Workload secrets

All paths are in clusters-work; [cluster.md](cluster.md) says how to find it.

A workload's Secret is a SealedSecret committed in the app's directory.
Plaintext never enters git or command output.

1. Generate app tokens with `openssl rand -hex 32`, and ask Wenxuan for values
   only they hold.
2. In the dev shell, seal each value from stdin. The first key of a new file
   also names the Secret:

   ```sh
   printf '%s' "$value" | just sealed-set gitops/apps/<name>/sealedsecret-<name>.yaml APP_TOKEN <name>/<name>
   printf '%s' "$other" | just sealed-set gitops/apps/<name>/sealedsecret-<name>.yaml OTHER_KEY
   ```

   Sealing uses the committed certificate, so it works offline.

3. List the file in the app's `kustomization.yaml` and read the keys with
   `secretKeyRef`.
4. Run `just validate`, commit and push. The Secret exists once ArgoCD has
   synced; `just sealed-status` confirms it. Pods read Secrets at start, so
   roll the Deployment after any rotation.

Never add an agenix file for a workload: agenix holds only host and bootstrap
credentials.
