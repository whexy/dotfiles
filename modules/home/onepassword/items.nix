# The 1Password item behind each name `op-sa` takes.
#
# References name the vault and item by ID: a service account reads one of
# those in one request, and one named by title in three. A vault's items are
# readable by every home its vault lists; `op item list --vault <vault>
# --format json` shows the IDs.
let
  vaults = import ./vaults.nix;
  dotfiles = "op://${vaults.dotfiles}";
  dotfiles-dev = "op://${vaults.dotfiles-dev}";
in
{
  # CLIProxyAPI gateway key
  ai-proxy-api-key = "${dotfiles}/vwqv3wce7ignojg6jizk3w4og4/credential";
  # magpie gateway key, made under Gateway → Gateway keys in its web UI
  magpie-api-key = "${dotfiles}/ebcowrtac4l4utbjmvffjjgliq/credential";
  # Cloudflare Access service token (dotfiles), which the gateways, the NAS,
  # and the Renpho data sit behind
  cf-access-dotfiles-id = "${dotfiles}/bymghpfwuph3s7reggrkr3utei/client_id";
  cf-access-dotfiles-secret = "${dotfiles}/bymghpfwuph3s7reggrkr3utei/client_secret";
  # OpenAI API key (transcribe), restricted to the Audio API
  openai-api-key = "${dotfiles}/nxbvnufjdzgk5amxoszz642x7a/credential";
  # kubeconfig clusters-work
  kube-clusters-work = "${dotfiles}/g44lgrkgr6wxm62wi24uljxlky/clusters-work.yaml";

  # Cloudflare API token (cf)
  cloudflare-api-token = "${dotfiles-dev}/faurdkxmf3cwer44d6etrs2i4y/credential";
  # AWS dotfiles: credential_process JSON
  aws-credentials = "${dotfiles-dev}/g2dbcf6dnknrvs76fmc2vuht5q/credential";
  # Woodpecker token
  woodpecker-token = "${dotfiles-dev}/3gy7xmof2jgpdbmunomo6kn7zm/credential";
  # App Store Connect API key
  app-store-connect-api-key = "${dotfiles-dev}/32alcoif3dzanwx7ginje4mucq/AuthKey_8QCF5687D8.p8";
}
