# Nushell developer extras: carapace, starship, and the nushell side of the
# shared tools.
{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.shell;
in
{
  config = lib.mkIf cfg.nushell.devExtras {
    programs = {
      carapace = {
        enable = true;
        enableNushellIntegration = true;
        enableZshIntegration = false;
        enableBashIntegration = false;
      };

      starship = {
        enable = true;
        enableNushellIntegration = true;
        enableZshIntegration = false;
        enableBashIntegration = false;
        settings = {
          add_newline = false;
          # Grey user@host on every prompt, matching the zsh p10k context segment.
          username = {
            show_always = true;
            style_user = "242";
            format = "[$user]($style)";
          };
          hostname = {
            ssh_only = false;
            style = "242";
            format = "[@$hostname]($style) ";
          };
        };
      };

      nushell = {
        shellAliases = {
          venv = "overlay use .venv/bin/activate.nu";
        };

        extraConfig = ''
          # nix run nixpkgs# shortcut
          def nr [pkg: string, ...rest: string] {
            ^nix run $"nixpkgs#($pkg)" -- ...$rest
          }
        '';
      };
    };
  };
}
