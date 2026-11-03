# Cluster access on every host without fetching kubeconfigs by hand.
#
# Each cluster's kubeconfig is its own agenix secret whose cluster, user,
# and context are all named after the cluster. Activation writes them all
# into ~/.kube/config, the file every Kubernetes client reads by default,
# so any process reaches them and `kubectx <cluster>` switches between them.
# That file holds only each cluster's address and CA: kubectl loads the
# client certificate through a credential plugin, which decrypts the secret
# into its own memory for each command.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.tooling.kube;
  home = config.home.homeDirectory;
  yq = lib.getExe pkgs.yq-go;
  kubeconfig = "${home}/.kube/config";
  secret = name: ../../../secrets/kube-${name}.age;

  # Decrypts the way agenix does, at the moment of use, so neither the plugin
  # nor activation waits for agenix's service to have run.
  decrypt = ''
    kube_decrypt() {
      local identities=() identity
      for identity in ${lib.escapeShellArgs config.age.identityPaths}; do
        [ -r "$identity" ] && identities+=(-i "$identity")
      done
      ${lib.getExe config.age.package} --decrypt "''${identities[@]}" "$1"
    }
  '';

  # The plugin kubectl runs, `kube-credential <cluster>`, printing the
  # client certificate as an ExecCredential.
  credential = pkgs.writeShellScriptBin "kube-credential" ''
    set -euo pipefail
    ${decrypt}
    case "$1" in
    ${lib.concatMapStrings (name: ''
      ${lib.escapeShellArg name}) secret=${secret name} ;;
    '') cfg.clusters}
    *)
      echo "kube-credential: no cluster $1" >&2
      exit 1
      ;;
    esac
    kube_decrypt "$secret" | CLUSTER=$1 ${yq} -o json '
      .users[] | select(.name == strenv(CLUSTER)) | .user | {
        "apiVersion": "client.authentication.k8s.io/v1",
        "kind": "ExecCredential",
        "status": {
          "clientCertificateData": (."client-certificate-data" | @base64d),
          "clientKeyData": (."client-key-data" | @base64d)
        }
      }'
  '';
  # Named through the profile, not the store, so the config stays valid
  # after the generation that wrote it is collected.
  credentialCommand = "${config.home.profileDirectory}/bin/kube-credential";

  # Replaces each cluster's entries, by name, with the secret's cluster and
  # the plugin as its user, and leaves every other entry alone. A context
  # already there is kept, so a namespace chosen with kubens survives. A
  # cluster whose secret cannot be decrypted keeps its last entries.
  writeClusters = lib.concatMapStrings (name: ''
    if kube_entry=$(kube_decrypt ${secret name} | CLUSTER=${lib.escapeShellArg name} ${yq} '{
      "cluster": (.clusters[] | select(.name == strenv(CLUSTER))),
      "context": (.contexts[] | select(.name == strenv(CLUSTER)))
    }'); then
      kube_config=$(printf '%s\n' "$kube_config" | CLUSTER=${lib.escapeShellArg name} ENTRY="$kube_entry" \
        COMMAND=${lib.escapeShellArg credentialCommand} ${yq} '
        (strenv(ENTRY) | from_yaml) as $entry |
        .clusters = ([.clusters[] | select(.name != strenv(CLUSTER))] + [$entry.cluster]) |
        .users = ([.users[] | select(.name != strenv(CLUSTER))] + [{
          "name": strenv(CLUSTER),
          "user": {
            "exec": {
              "apiVersion": "client.authentication.k8s.io/v1",
              "command": strenv(COMMAND),
              "args": [strenv(CLUSTER)],
              "interactiveMode": "Never"
            }
          }
        }]) |
        .contexts = ([.contexts[] | select(.name != strenv(CLUSTER))] +
          [([.contexts[] | select(.name == strenv(CLUSTER))] + [$entry.context]) | .[0]])
      ')
    else
      warnEcho "Could not decrypt the kubeconfig of ${name}; keeping its last entries"
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

      activation.kubeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${decrypt}
        kube_config=$(cat ${lib.escapeShellArg kubeconfig} 2>/dev/null || true)
        kube_config=$(printf '%s\n' "$kube_config" | ${yq} '
          .apiVersion = "v1" | .kind = "Config" |
          .clusters = (.clusters // []) | .users = (.users // []) | .contexts = (.contexts // [])
        ')
        ${writeClusters}
        ${lib.optionalString (cfg.clusters != [ ]) ''
          # Without a current-context kubectl reaches no cluster at all; one
          # kubectx chose, even unset, stays.
          kube_config=$(printf '%s\n' "$kube_config" | FIRST=${lib.escapeShellArg (lib.head cfg.clusters)} ${yq} '
            .["current-context"] = (.["current-context"] // strenv(FIRST))
          ')
        ''}

        if [ "$kube_config" != "$(cat ${lib.escapeShellArg kubeconfig} 2>/dev/null)" ]; then
          run mkdir -p ${lib.escapeShellArg (dirOf kubeconfig)}
          # coreutils install rejects /dev/stdin as a source on Darwin.
          kube_tmp=$(mktemp)
          printf '%s\n' "$kube_config" >"$kube_tmp"
          run install -m 600 "$kube_tmp" ${lib.escapeShellArg kubeconfig}
          rm -f "$kube_tmp"
        fi

        # Earlier generations kept each cluster in a file of its own here.
        ${lib.concatMapStrings (name: ''
          run rm -f ${lib.escapeShellArg "${home}/.kube/clusters/${name}"}
        '') cfg.clusters}
        run rmdir --ignore-fail-on-non-empty ${lib.escapeShellArg "${home}/.kube/clusters"} 2>/dev/null || true
      '';
    };
  };
}
