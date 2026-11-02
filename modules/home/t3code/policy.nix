# The managed policy the T3 Code server applies. No policy lives here: the
# server's wrapper runs `t3code-policy resolve` at each start, which fetches
# it from the policy editor, checks it with the server's own binary, and keeps
# the last good copy for when the editor is unreachable.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.t3code;
  t3 = lib.getExe' cfg.finalPackage "t3";
  editorUrl = "https://t3-policy.at-basking.ts.net/";

  # With the path unset, T3 would look for the machine's own policy; a path
  # set to a file that cannot exist means no policy at all.
  none = "${pkgs.emptyDirectory}/policy.json";

  command = pkgs.writeShellApplication {
    name = "t3code-policy";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      t3=${t3}
      no_policy=${none}
      editor_url=${editorUrl}
      policy_url=''${T3CODE_POLICY_URL:-${editorUrl}policy.json}
      alert_url=''${T3CODE_POLICY_ALERT_URL:-https://n8n.clusters.work/webhook/t3code-alert}
      # Nix's curl knows no CA bundle on macOS or non-NixOS Linux.
      export CURL_CA_BUNDLE=''${CURL_CA_BUNDLE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}
    ''
    + builtins.readFile ./policy.sh;
  };
in
{
  options.dotfiles.t3code.policy = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    internal = true;
    readOnly = true;
    default = {
      command = lib.getExe command;
      inherit none;
    };
    description = "The policy resolver the server's wrapper runs, and the path that means no policy.";
  };

  config = lib.mkIf (cfg.enable && cfg.server.enable) {
    home.packages = [ command ];
  };
}
