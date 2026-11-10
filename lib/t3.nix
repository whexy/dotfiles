# What the T3 Code server module, t3-pair and the T3 checks share.
{ tailnetHost }:
{
  # Loopback port of the server, which Tailscale Serve and the public tunnel
  # proxy to.
  port = 3773;
  # HTTPS port Tailscale Serve publishes the server on.
  tailnetPort = 35338;
  # n8n workflow that forwards alerts to WeChat: the policy command's, and
  # CI's when its repair task does not take a failure (.woodpecker.yml).
  alertWebhook = "https://n8n.clusters.work/webhook/t3code-alert";
  # Where the managed policy is edited.
  policyEditor = "https://${tailnetHost "t3-policy"}/";
  # Hosts whose T3 Code servers t3-mesh links to one another, each in both
  # directions. The host running it reaches the others over Tailscale SSH.
  mesh = [
    "mudd"
    "deimos"
    "neith"
    "phobos"
    "seeley"
    "sheridan"
    "zoozve"
  ];
}
