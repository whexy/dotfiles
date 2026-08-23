# System Message of the Day (MOTD) banner module.
{
  config,
  lib,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.shell;
in
{
  config = lib.mkIf cfg.motd.enable {
    home.packages = [
      perSystem.self.motd
    ];

    programs.zsh.initContent = lib.mkIf cfg.zsh.enable (
      lib.mkOrder 1600 ''
        # Run motd on interactive top-level shell sessions
        if [[ -o interactive && -z "$TMUX" && -z "$ZELLIJ" && -z "$MOTD_SHOWN" ]]; then
          export MOTD_SHOWN=1
          ${perSystem.self.motd}/bin/motd
        fi
      ''
    );
  };
}
