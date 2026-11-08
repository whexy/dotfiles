# Cluster access on every host without fetching kubeconfigs by hand.
#
# Each cluster's kubeconfig is its own agenix secret whose cluster, user,
# and context are all named after the cluster. Activation builds
# ~/.kube/config from them, the file every Kubernetes client reads by
# default, so any process reaches them and `kubectx <cluster>` switches
# between them. This module owns that file: entries other tools add to it
# are dropped at the next activation.
{
  config,
  pkgs,
  lib,
  flake,
  ...
}:
let
  cfg = config.dotfiles.tooling.kube;
  relay = config.dotfiles.tailnetRelay;
  decrypt = flake.lib.agenixDecrypt {
    inherit pkgs;
    inherit (config.age) identityPaths package;
  };

  writeConfig = pkgs.writeShellApplication {
    name = "kube-write-config";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.diffutils
      pkgs.kubectl
    ];
    text = ''
      target=$1
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT

      # Checked one by one, so a malformed secret cannot block the merge or
      # shadow another cluster's entries.
      files=()
      add() {
        if ${lib.getExe decrypt} -o "$work/$1" "$2" &&
          [ "$(KUBECONFIG="$work/$1" kubectl config view --flatten 2>/dev/null \
            -o jsonpath="{.contexts[?(@.name==\"$1\")].context.cluster}/{.contexts[?(@.name==\"$1\")].context.user}")" = "$1/$1" ]; then
          files+=("$work/$1")
        else
          echo "kube: skipping $1: cannot decrypt it, or it is not a self-contained kubeconfig naming its cluster, user and context $1" >&2
        fi
      }
      ${lib.concatMapStrings (name: ''
        add ${lib.escapeShellArg name} ${../../../secrets/kube-${name}.age}
      '') cfg.clusters}
      if [ ''${#files[@]} -eq 0 ]; then
        echo "kube: no cluster available; leaving $target as it is" >&2
        exit 0
      fi

      # Built from the secrets alone, so rotated credentials always land and
      # removed clusters disappear. Only the context kubectx chose and the
      # namespace kubens set on it carry over.
      current=$(kubectl --kubeconfig "$target" config current-context 2>/dev/null || true)
      namespace=$(kubectl --kubeconfig "$target" config view --minify \
        -o jsonpath='{.contexts[0].context.namespace}' 2>/dev/null || true)

      KUBECONFIG=$(IFS=:; echo "''${files[*]}") kubectl config view --flatten >"$work/config"
      export KUBECONFIG="$work/config"
      ${lib.optionalString relay.enable ''
        # The API servers are tailnet hosts. Their certificates are checked
        # against the kubeconfig's CA, so the proxy port needs no check.
        for file in "''${files[@]}"; do
          kubectl config set-cluster "$(basename "$file")" --proxy-url=${relay.proxy.url} >/dev/null
        done
      ''}      if [ -n "$current" ] && kubectl config get-contexts "$current" >/dev/null 2>&1; then
        kubectl config use-context "$current" >/dev/null
        [ -z "$namespace" ] || kubectl config set-context "$current" --namespace "$namespace" >/dev/null
      else
        kubectl config use-context "$(basename "''${files[0]}")" >/dev/null
      fi

      if ! cmp -s "$work/config" "$target"; then
        mkdir -p "$(dirname "$target")"
        staged=$(mktemp "$target.XXXXXX")
        trap 'rm -rf "$work" "$staged"' EXIT
        cat "$work/config" >"$staged"
        mv -f "$staged" "$target"
      fi
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    home = {
      packages = [ pkgs.kubectx ];

      # agenix decrypts from a systemd user service or launchd agent that may
      # run after activation, so the secrets are read directly.
      activation.kubeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run ${lib.getExe writeConfig} ${lib.escapeShellArg "${config.home.homeDirectory}/.kube/config"} \
          || warnEcho "~/.kube/config was not updated"
      '';
    };
  };
}
