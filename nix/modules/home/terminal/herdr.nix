# herdr terminal workspace manager (from llm-agents.nix, cached on cache.numtide.com)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.terminal;
in
{
  config = lib.mkIf cfg.herdr.enable {
    home.packages = [ pkgs.llm-agents.herdr ];

    xdg.configFile."herdr/config.toml".text = ''
      [theme]
      name = "gruvbox"
    '';
  };
}
