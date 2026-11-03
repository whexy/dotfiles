# The t3code-policy command. A plain function, so checks/t3-policy runs it
# against a fixture policy server without evaluating a home.
{
  pkgs,
  lib,
  t3,
  url,
  editorUrl,
  none,
  # Shell commands that test whether the server service runs, and restart it.
  server,
}:
pkgs.writeShellApplication {
  name = "t3code-policy";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.curl
    pkgs.flock
    pkgs.gnugrep
    pkgs.jq
  ];
  text = ''
    t3=${t3}
    no_policy=${none}
    editor_url=${lib.escapeShellArg editorUrl}
    policy_url=''${T3CODE_POLICY_URL:-${lib.escapeShellArg url}}
    alert_url=''${T3CODE_POLICY_ALERT_URL:-https://n8n.clusters.work/webhook/t3code-alert}
    # Nix's curl knows no CA bundle on macOS or non-NixOS Linux.
    export CURL_CA_BUNDLE=''${CURL_CA_BUNDLE:-${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt}
    server_running() { ${server.running}; }
    restart_server() { ${server.restart}; }
  ''
  + builtins.readFile ./policy.sh;
}
