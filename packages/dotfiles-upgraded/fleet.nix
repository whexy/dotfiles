# What every dotfiles-upgraded daemon shares: where it fetches from, where it
# reports, how it hears of new commits, and how its Linux units reload. A
# plain function; flake.lib re-exports each value under its own name.
{ lib, tailnetHost }:
{
  # Where this repo is published. Machines fetch their own definition from
  # here when they upgrade themselves, so it is a runtime input to the
  # configuration rather than a documentation string. Changing the repo
  # location means changing it here.
  upstreamRef = "github:whexy/dotfiles";

  # n8n workflow (n8n/failure-report.json) that files each switch a daemon
  # gives up on as a GitHub issue. It holds the GitHub credential, so hosts
  # carry only its token, secrets/upgrade-webhook-token.age.
  upgradeFailureWebhook = "https://n8n.clusters.work/webhook/dotfiles-upgrade-failure";

  # When a push to master passes CI, the pipeline announces the commit on this
  # ntfy topic (clusters-work, docs/ntfy.md), signed with the key whose public
  # half is below; the private half is the Woodpecker secret
  # rollout_signing_key. Daemons subscribe to it instead of polling GitHub
  # (README.md).
  rollout = {
    relay = "https://${tailnetHost "ntfy"}";
    topic = "dotfiles-rollout";
    publicKey = "9TsY4W+qgm9Lz07eKWbRMUiLQwB8j3E1M0sPVpZS+FE=";
  };

  # ExecReload of the Linux units, which a switch reloads when it changes
  # them. That switch is usually the daemon's own, and restarting the daemon
  # during it would kill the rebuild before the daemon records the result.
  # The reload instead queues a restart behind the lock the daemon holds for
  # the whole rebuild, in a transient unit so the restart does not stop the
  # waiter along with the daemon. A failure to queue it must not fail the
  # switch, hence the "-".
  upgraderReload =
    {
      systemd,
      util-linux,
      stateDir,
      user,
    }:
    let
      scope = lib.optional user "--user";
    in
    "-"
    + lib.escapeShellArgs (
      [ "${systemd}/bin/systemd-run" ]
      ++ scope
      ++ [
        "--no-block"
        "--collect"
        "--quiet"
        "--unit=dotfiles-upgraded-restart"
        "${util-linux}/bin/flock"
        "${stateDir}/lock"
        "${systemd}/bin/systemctl"
      ]
      ++ scope
      ++ [
        "try-restart"
        "dotfiles-upgraded.service"
      ]
    );
}
