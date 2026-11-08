# What every agent launcher shares.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.agents.launcher;
in
{
  options.dotfiles.agents.launcher = {
    gitConfig = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      # Agents commit as the user but did not write the code, so they leave
      # commits and tags unsigned while the user's own git keeps signing. The
      # include must come first: a later value wins.
      default = pkgs.writeText "agent-gitconfig" ''
        [include]
          path = ${config.xdg.configHome}/git/config
        [commit]
          gpgSign = false
        [tag]
          gpgSign = false
      '';
      defaultText = lib.literalMD "the user's git config with commit and tag signing off";
      description = "Global git config of every agent session.";
    };

    relayListeners = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Tailnet relay addresses the agents connect to directly, such as MCP
        servers'. Every launcher refuses to start its agent unless this user
        holds them (`dotfiles.tailnetRelay.checker`).
      '';
    };

    prelude = lib.mkOption {
      type = lib.types.lines;
      readOnly = true;
      # The agent and its tool shells inherit what these lines export, so a
      # secret must never go here; a tool that needs one loads it in its own
      # wrapper (see `transcribe`).
      default = ''
        export GIT_CONFIG_GLOBAL=${cfg.gitConfig}
      ''
      + lib.optionalString (cfg.relayListeners != [ ]) ''
        ${config.dotfiles.tailnetRelay.checker} ${lib.escapeShellArgs cfg.relayListeners} || exit 1
      '';
      defaultText = lib.literalMD "an export of `gitConfig` as `GIT_CONFIG_GLOBAL`, and the check of `relayListeners`";
      description = "Shell lines every agent launcher runs before starting its agent.";
    };
  };
}
