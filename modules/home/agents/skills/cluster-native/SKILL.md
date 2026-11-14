---
name: cluster-native
description: Design a project around the services Wenxuan's cluster already runs (shared PostgreSQL, Ceph volumes, WDL Workers, LLM gateways, web search, WeChat, alerting, egress paths) instead of bundling its own. Use when asked to make something "cluster-native", or to design or plan a project that will run on the cluster, before writing code. deploy-to-cluster takes over once the design is settled.
---

# Cluster-native design

A cluster-native project uses the services the cluster already runs instead
of bringing its own, and fits the cluster's rules for exposure, state and
secrets. This skill covers the design. `deploy-to-cluster` builds the repo,
CI and manifests after the user approves it.

## Read the catalog

The services, their in-cluster addresses, how a Pod gets in and how durable
each one is are in clusters-work's `docs/platform-services.md`. It is the only
current list, so read it before proposing anything, and take names and
addresses from it, never from memory:

```sh
gh api -H 'Accept: application/vnd.github.raw' repos/whexy/clusters-work/contents/docs/platform-services.md
```

Read the owning doc of every service you pick; the catalog links to each one
(`.../contents/docs/<doc>.md`, same command). If the project accepts any
connection, also read `docs/network-exposure.md`. Its rules are binding.

## Design

1. **List the needs.** State, compute, AI, search, notifications, outbound
   calls, and who calls the project: people, devices, webhooks, other
   services.
2. **Map each need to a catalog service.** For example, a database belongs
   in the shared PostgreSQL, not a sidecar. Models go through the LLM
   gateways, not provider keys in the app. Notifying Wenxuan goes through
   wechat-relay or alerting.
3. **Choose where the code runs.** A WDL Worker suits request handlers, cron
   jobs and queue consumers whose state fits KV, D1 or Durable Objects. A
   container Deployment suits everything else. A Worker reaches only the
   public internet: it cannot call the database, the gateways or any other
   in-cluster address.
4. **Place every piece of state.** Say which store holds it and what backs it
   up. When the catalog marks a store staging or without backup (WDL today),
   say so to the user and keep only data that can be lost there.
5. **Classify each surface** as tailnet, public or internal by its callers,
   per the network-exposure doc. A project other apps will call needs a row
   in the catalog when it deploys.

A need the catalog does not cover, such as a durable object store, is the
user's decision. Give the options, such as bundling it in the app or adding a
cluster service, and do not quietly invent either.

## Hand the design back

Before any code, give the user a short design:

- each need, the service chosen, its address and how the Pod gets in;
- the credentials the project needs, each as a SealedSecret;
- where each piece of state lives and how it is backed up;
- each surface's tier;
- the decisions only Wenxuan can make: an entry in another app's
  NetworkPolicy, a tailnet ACL grant, a public host, and any data placed on a
  staging service.

Once it is approved, continue with `deploy-to-cluster`.
