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

    # Herdr's first-run flow persists its result by rewriting config.toml, which
    # fails on the read-only store path. Declaring the post-onboarding value
    # keeps the file immutable and skips the flow.
    xdg.configFile."herdr/config.toml".text = ''
      onboarding = false

      [theme]
      name = "gruvbox"

      [ui.toast]
      delivery = "terminal"

      [experimental]
      kitty_graphics = true
    '';
  };
}
