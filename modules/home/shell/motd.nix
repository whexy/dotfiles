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
          # Powerlevel10k's instant prompt captures startup output through a file,
          # so preserve the terminal's styling and dimensions for the later replay.
          MOTD_COLOR=always MOTD_COLUMNS="$COLUMNS" ${perSystem.self.motd}/bin/motd
        fi
      ''
    );
  };
}
