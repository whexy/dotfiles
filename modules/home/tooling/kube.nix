# Cluster access on every host without fetching kubeconfigs by hand.
#
# Each cluster's kubeconfig is a 1Password document whose cluster, user, and
# context are all named after the cluster, so the files merge through
# KUBECONFIG without colliding and `kubectx <cluster>` switches between them.
# The files on disk hold only the cluster's address and CA: kubectl loads the
# client certificate from 1Password through a credential plugin, for each
# command, into its own memory.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.tooling.kube;
  home = config.home.homeDirectory;
  opSa = lib.getExe config.dotfiles.onepassword.package;
  yq = lib.getExe pkgs.yq-go;

  # kubectl writes current-context to the first KUBECONFIG file, so it must
  # be a writable file of its own.
  stateConfig = "${home}/.kube/config";
  clusterPath = name: "${home}/.kube/clusters/${name}";
  kubeconfig = lib.concatStringsSep ":" ([ stateConfig ] ++ map clusterPath cfg.clusters);

  # The plugin kubectl runs, `kube-credential <cluster>`, printing the
  # client certificate as an ExecCredential.
  credential = pkgs.writeShellScriptBin "kube-credential" ''
    set -euo pipefail
    ${opSa} read "kube-$1" | CLUSTER=$1 ${yq} -o json '
      .users[] | select(.name == strenv(CLUSTER)) | .user | {
        "apiVersion": "client.authentication.k8s.io/v1",
        "kind": "ExecCredential",
        "status": {
          "clientCertificateData": (."client-certificate-data" | @base64d),
          "clientKeyData": (."client-key-data" | @base64d)
        }
      }'
  '';
  # Named through the profile, not the store, so the files stay valid after
  # the generation that wrote them is collected.
  credentialCommand = "${config.home.profileDirectory}/bin/kube-credential";

  # The cluster's kubeconfig with its user's credentials replaced by the
  # plugin. A cluster whose document cannot be loaded keeps its last file.
  writeClusters = lib.concatMapStrings (name: ''
    if cluster_config=$(${opSa} read ${lib.escapeShellArg "kube-${name}"} | CLUSTER=${lib.escapeShellArg name} COMMAND=${lib.escapeShellArg credentialCommand} ${yq} '
      (.users[] | select(.name == strenv(CLUSTER))).user = {
        "exec": {
          "apiVersion": "client.authentication.k8s.io/v1",
          "command": strenv(COMMAND),
          "args": [strenv(CLUSTER)],
          "interactiveMode": "Never"
        }
      }'); then
      run mkdir -p ${lib.escapeShellArg (dirOf (clusterPath name))}
      if [ "$cluster_config" != "$(cat ${lib.escapeShellArg (clusterPath name)} 2>/dev/null)" ]; then
        # coreutils install rejects /dev/stdin as a source on Darwin.
        cluster_tmp=$(mktemp)
        printf '%s\n' "$cluster_config" >"$cluster_tmp"
        run install -m 600 "$cluster_tmp" ${lib.escapeShellArg (clusterPath name)}
        rm -f "$cluster_tmp"
      fi
    else
      warnEcho "Could not load the kubeconfig of ${name} from 1Password; keeping the last one"
    fi
  '') cfg.clusters;
in
{
  config = lib.mkIf cfg.enable {
    home = {
      packages = [
        pkgs.kubectx
        credential
      ];

      # kubectl falls back to the last KUBECONFIG file when none exist, and
      # kubectx cannot parse an empty one, so seed a minimal valid config.
      activation.kubeStateConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -s ${lib.escapeShellArg stateConfig} ]; then
          run mkdir -p ${lib.escapeShellArg (dirOf stateConfig)}
          run install -m 600 ${pkgs.writeText "kubeconfig" "apiVersion: v1\nkind: Config\n"} \
            ${lib.escapeShellArg stateConfig}
        fi
      '';
      activation.kubeClusters = lib.hm.dag.entryAfter [ "writeBoundary" ] writeClusters;
    };

    # Not home.sessionVariables: its script is skipped in any shell that
    # inherits __HM_SESS_VARS_SOURCED, such as one under a tmux or zellij
    # server started before this module was activated. Only a fallback: zshenv
    # runs in every zsh, including scripts started with a cluster chosen.
    programs = {
      zsh.envExtra = lib.mkIf config.dotfiles.shell.zsh.enable ''
        export KUBECONFIG=''${KUBECONFIG:-${lib.escapeShellArg kubeconfig}}
      '';
      nushell.environmentVariables.KUBECONFIG = lib.hm.nushell.mkNushellInline "$env.KUBECONFIG? | default --empty ${builtins.toJSON kubeconfig}";
    };
  };
}
