{
  config,
  lib,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.ssh.agentRouter;
  package = perSystem.self.ssh-agent-router;
  router = "${package}/bin/ssh-agent-router";
in
{
  options.dotfiles.ssh.agentRouter.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.dotfiles.ssh.enable;
    description = "Route persistent SSH terminal sessions to the newest live forwarded agent.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ package ];

    # SSH_AUTH_SOCK wins when present; local desktop shells retain the
    # platform-specific 1Password IdentityAgent fallback in the default block.
    programs = {
      ssh.settings.forwarded-agent = {
        header = ''Match exec "${package}/libexec/ssh-agent-router/has-agent"'';
        IdentityAgent = "SSH_AUTH_SOCK";
      };

      # Inside an SSH session `router shell` depends only on SSH_AUTH_SOCK, TMUX
      # and ZELLIJ, and repeating it for the same values changes nothing while
      # the daemon runs. The exported marker lets child shells, such as the
      # `$SHELL -c` behind OpenSSH's Match exec, skip it; a new SSH login or
      # multiplexer pane still routes.
      zsh.envExtra = lib.mkIf config.dotfiles.shell.zsh.enable ''
        if [[ -n "$SSH_CONNECTION" && "$_SSH_AGENT_ROUTED" != "$TMUX$ZELLIJ:$SSH_AUTH_SOCK" ]]; then
          if _agent_socket="$(${router} shell)"; then
            if [[ -n "$_agent_socket" ]]; then
              export SSH_AUTH_SOCK="$_agent_socket"
            fi
            export _SSH_AGENT_ROUTED="$TMUX$ZELLIJ:$SSH_AUTH_SOCK"
          fi
          unset _agent_socket
        fi
      '';

      nushell.extraEnv = lib.mkIf config.dotfiles.shell.nushell.enable ''
        if ($env.SSH_CONNECTION? | default "") != "" {
          let context = $"($env.TMUX? | default "")($env.ZELLIJ? | default ""):"
          if ($env._SSH_AGENT_ROUTED? | default "") != $"($context)($env.SSH_AUTH_SOCK? | default "")" {
            let agent = (^${router} shell | complete)
            if $agent.exit_code == 0 {
              if ($agent.stdout | str trim) != "" {
                $env.SSH_AUTH_SOCK = ($agent.stdout | str trim)
              }
              $env._SSH_AGENT_ROUTED = $"($context)($env.SSH_AUTH_SOCK? | default "")"
            }
          }
        }
      '';
    };
  };
}
