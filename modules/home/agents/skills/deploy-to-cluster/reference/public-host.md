# Public host (only when Wenxuan asks)

All paths are in clusters-work; [cluster.md](cluster.md) says how to find it.

- **Routing:** add an `ingressClassName: nginx` Ingress with
  `host: <name>.clusters.work` and no TLS block. Cloudflare terminates TLS,
  and the `*.clusters.work` tunnel route already forwards to ingress-nginx.
- **Authentication:** a public host is reachable from the whole internet.
  Either the app authenticates every route itself, or Wenxuan puts a
  Cloudflare Access application in front of it. Access lives in the Zero
  Trust dashboard, not in git, and it blocks webhooks and machine clients.
- **Paths:** route only the paths that must be public.
- **Long-lived responses:** streaming or long-lived responses need
  `nginx.ingress.kubernetes.io/proxy-buffering: "off"` plus raised
  `proxy-read-timeout` and `proxy-send-timeout`. Large uploads need
  `proxy-body-size`; Cloudflare's free plan caps request bodies at 100 MB.
