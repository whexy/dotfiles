# Image-update webhook

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
