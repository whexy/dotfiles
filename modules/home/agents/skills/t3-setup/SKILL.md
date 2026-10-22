---
name: t3-setup
description: How Wenxuan's T3 Code servers are reached without T3 Connect - public and tailnet URLs, pairing, and webhook URLs. Use when creating or sharing a T3 Code webhook or scheduled task (especially when schedule_task returns no webhookUrl), when T3 Connect comes up, when pairing or connecting a T3 environment or host, or when you need a T3 server's public or tailnet URL.
---

# T3 Code on Wenxuan's hosts

Wenxuan does not use T3 Connect. Every host whose T3 Code server runs on the
tailnet has two routes to it instead, both set up by dotfiles:

| Route                               | URL                                      |
| ----------------------------------- | ---------------------------------------- |
| Public, through a Cloudflare tunnel | `https://<host>-t3.clusters.work`        |
| Tailnet, through Tailscale Serve    | `https://<host>.at-basking.ts.net:35338` |

`<host>` is the dotfiles host name, which is also `hostname -s`. A host whose
server listens on its LAN instead has neither route.

The public route is up only if T3's descriptor answers. Every other
`*.clusters.work` name also answers, with a 302 to whexy.com/404, so a status
code proves nothing:

```sh
curl -s "https://$(hostname -s)-t3.clusters.work/.well-known/t3/environment" | jq -r .environmentId
```

## Webhooks

Without T3 Connect, `schedule_task` returns no `webhookUrl`, and its
description tells you to send the user to T3 Connect. Don't: every T3 server
answers webhooks itself at `/api/hooks/<task id>/<token>`, so build the URL on
the public route.

1. Create the task with `schedule_task` and keep its `scheduledTaskId`.
2. On the host whose server owns the task (the one you run on, when T3 Code
   started you), read the token from the server's database. Open it read-only:
   it is the live T3 Code database.

   ```sh
   id='scheduled-task:...'   # the scheduledTaskId
   token=$(sqlite3 -readonly ~/.t3/userdata/statev2.sqlite \
     "SELECT webhook_token FROM scheduled_tasks WHERE task_id = '$id'")
   echo "https://$(hostname -s)-t3.clusters.work/api/hooks/${id/:/%3A}/$token"
   ```

   Without `sqlite3` on `PATH`, run it as `nix shell nixpkgs#sqlite -c sqlite3 ...`.

3. Check the public route is up. If it isn't, say this host has no public
   route: GitHub and other outside senders cannot reach the tailnet URL.
4. Give Wenxuan the full URL, as T3 Connect would. The token is the
   credential: never commit it or write it into a repository.

To test without starting a run:

- A made-up task id returns 404 `{"error":"hook_not_found"}`, which proves the
  route.
- On a task with filters, POST a body they reject. It returns 202 with
  `x-t3-hook-outcome: filtered`.

Every POST a task accepts starts a run (`x-t3-hook-outcome: accepted`), so
never test-POST to a task without filters.

## Pairing

`t3-pair [host]` mints a single-use pairing link for the host's server (this
machine when no host is given) and prefers the public URL. Paste it into
T3 Code under Settings → Connections → Add environment.

Pair over the public URL. The client then learns the tailnet route from the
server and uses it wherever it works; a client paired over the tailnet never
learns the public route.

wsl has no tailnet node of its own: it is reached through its Windows host's
node, `whexygamemaster`, and `ssh wsl` does not resolve from other hosts. Run
`t3-pair` on wsl itself.
