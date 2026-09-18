{
  config,
  lib,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.ssh.agentRouter;
  router = "${perSystem.self.ssh-agent-router}/bin/ssh-agent-router";
in
{
  options.dotfiles.ssh.agentRouter.enable = lib.mkOption {
    type = lib.types.bool;
    default = config.dotfiles.ssh.enable;
    description = "Route persistent SSH terminal sessions to the newest live forwarded agent.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ perSystem.self.ssh-agent-router ];

    # SSH_AUTH_SOCK wins when present; local desktop shells retain the
    # platform-specific 1Password IdentityAgent fallback in the default block.
    programs = {
      ssh.settings.forwarded-agent = {
        header = ''Match exec "${router} has-agent"'';
        IdentityAgent = "SSH_AUTH_SOCK";
      };

      zsh.envExtra = lib.mkIf config.dotfiles.shell.zsh.enable ''
        if [[ -n "$SSH_CONNECTION" ]]; then
          if _agent_socket="$(${router} shell)"; then
            if [[ -n "$_agent_socket" ]]; then
              export SSH_AUTH_SOCK="$_agent_socket"
            fi
          fi
          unset _agent_socket
        fi
      '';

      nushell.extraEnv = lib.mkIf config.dotfiles.shell.nushell.enable ''
        if ($env.SSH_CONNECTION? | default "") != "" {
          let agent = (^${router} shell | complete)
          if $agent.exit_code == 0 and ($agent.stdout | str trim) != "" {
            $env.SSH_AUTH_SOCK = ($agent.stdout | str trim)
          }
        }
      '';
    };
  };
}
