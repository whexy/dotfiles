# Cluster access on every host without fetching kubeconfigs by hand.
#
# Each cluster's kubeconfig is its own agenix secret whose cluster, user,
# and context are all named after the cluster, so the files merge through
# KUBECONFIG without colliding and `kubectx <cluster>` switches between them.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.dotfiles.tooling.kube;
  home = config.home.homeDirectory;

  # kubectl writes current-context to the first KUBECONFIG file, so it must
  # be a writable file outside agenix's read-only, re-decrypted secrets.
  stateConfig = "${home}/.kube/config";
  clusterPath = name: "${home}/.kube/clusters/${name}";
  kubeconfig = lib.concatStringsSep ":" ([ stateConfig ] ++ map clusterPath cfg.clusters);
in
{
  config = lib.mkIf cfg.enable {
    home = {
      packages = [ pkgs.kubectx ];

      # kubectl falls back to the last KUBECONFIG file when none exist, and
      # kubectx cannot parse an empty one, so seed a minimal valid config.
      activation.kubeStateConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -s ${lib.escapeShellArg stateConfig} ]; then
          run mkdir -p ${lib.escapeShellArg (dirOf stateConfig)}
          run install -m 600 ${pkgs.writeText "kubeconfig" "apiVersion: v1\nkind: Config\n"} \
            ${lib.escapeShellArg stateConfig}
        fi
      '';
    };

    # Not home.sessionVariables: its script is skipped in any shell that
    # inherits __HM_SESS_VARS_SOURCED, such as one under a tmux or zellij
    # server started before this module was activated.
    programs = {
      zsh.envExtra = lib.mkIf config.dotfiles.shell.zsh.enable ''
        export KUBECONFIG=${lib.escapeShellArg kubeconfig}
      '';
      nushell.environmentVariables.KUBECONFIG = kubeconfig;
    };

    age.secrets = lib.listToAttrs (
      map (name: {
        name = "kube-${name}";
        value = {
          file = ../../../secrets/kube-${name}.age;
          path = clusterPath name;
          # kubectx opens every KUBECONFIG file read-write, even to only
          # switch context. Its rewrites are lost on the next decryption.
          mode = "0600";
        };
      }) cfg.clusters
    );
  };
}
