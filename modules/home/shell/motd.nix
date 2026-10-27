# System Message of the Day (MOTD) banner module.
args@{
  config,
  lib,
  perSystem,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.shell;

  # An integrated home switches with its system, so the system's daemon
  # upgrades it; a standalone home runs its own.
  autoUpgrade =
    if osConfig != null then osConfig.dotfiles.system.autoUpgrade else config.dotfiles.autoUpgrade;
  flags = [
    "--profile=${if osConfig != null then "system" else "home-manager"}"
  ]
  ++ lib.optional autoUpgrade.enable "--updater-status=${autoUpgrade.stateDir}/status.json";

  motd = pkgs.symlinkJoin {
    inherit (perSystem.self.motd) name meta;
    paths = [ perSystem.self.motd ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/motd ${
        lib.concatMapStringsSep " " (flag: "--add-flag ${lib.escapeShellArg flag}") flags
      }
    '';
  };
in
{
  config = lib.mkIf cfg.motd.enable {
    home.packages = [ motd ];

    programs.zsh.initContent = lib.mkIf cfg.zsh.enable (
      lib.mkOrder 1600 ''
        # Run motd on interactive top-level shell sessions
        if [[ -o interactive && -z "$TMUX" && -z "$ZELLIJ" && -z "$MOTD_SHOWN" ]]; then
          export MOTD_SHOWN=1
          # Powerlevel10k's instant prompt captures startup output through a file,
          # so preserve the terminal's styling and dimensions for the later replay.
          MOTD_COLOR=always MOTD_COLUMNS="$COLUMNS" ${motd}/bin/motd
        fi
      ''
    );
  };
}
