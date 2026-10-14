# Image-update webhook

A repository webhook makes argocd-image-updater check as soon as a package is
published; its 30-minute poll is only the fallback. User-owned packages send
`package` events to repository webhooks only, and only for packages linked to
that repository through the `source` label.

```sh
secret=$(kubectl -n argocd get secret argocd-image-updater-secret \
  -o jsonpath='{.data.webhook\.ghcr-secret}' | base64 -d)
gh api repos/whexy/<name>/hooks --method POST --silent \
  -f name=web -F active=true -f 'events[]=package' \
  -f 'config[url]=https://image-updater.clusters.work/webhook?type=ghcr.io' \
  -f 'config[content_type]=json' -f "config[secret]=$secret"
unset secret
```

Reading it needs the clusters-work dev shell's kubeconfig. If `kubectl`
cannot reach the cluster on this machine, ask Wenxuan. Never print the secret.
