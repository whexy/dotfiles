# Public host (only when Wenxuan asks)

All paths are in clusters-work; [cluster.md](cluster.md) says how to find it.
Its `docs/network-exposure.md` is binding: read it before publishing anything.

- **Which surfaces:** publish exactly the paths that callers off the tailnet
  use: webhooks, CLIs and agents with a token, devices, public visitors.
  Browser administration stays on the tailnet.
- **Routing:** copy `templates/cluster/gitops/apps/NAME/httproute.yaml` to
  `gitops/apps/<name>/httproute.yaml`, list only the public paths, and add it
  to the kustomization. The `*.clusters.work` tunnel route already forwards
  every subdomain to the public Gateway, so the route is live as soon as
  ArgoCD applies it. There is no Ingress for public traffic; the API server
  rejects any Ingress class but `tailscale`.
- **NetworkPolicy:** add the public Gateway to the app's allow policy in
  `networkpolicy.yaml`; the block is in `docs/network-exposure.md`.
- **Authentication:** a public host is reachable from the whole internet.
  Either the app authenticates every public path itself, or Wenxuan puts a
  Cloudflare Access application in front of it. Access lives in the Zero
  Trust dashboard, not in git, and it blocks webhooks and machine clients.
  Add the hostname to Access before the route exists.
- **Matching:** `PathPrefix` matches whole path segments, a
  `RegularExpression` must match the entire path, and matching is
  case-sensitive. Add `method: POST` to a webhook path.
- **Long-lived responses and uploads** need no settings: the Gateway streams,
  has no response time limit, allows an hour of idle time and sets no body
  limit. Cloudflare's free plan caps request bodies at 100 MB.
