# VCS group: git and git-adjacent tools.
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
in
{
  options.dotfiles.vcs = {
    git = {
      enable = lib.mkEnableOption "git";
      command.enable = lib.mkEnableOption ''
        the git command on Linux, also in homes where `git.enable` does not
        configure git. macOS keeps Apple's git, which avoids a keychain
        prompt
      '';
      # Integrated homes sign with the 1Password app the system installs.
      opSshSigning = lib.mkOption {
        type = lib.types.bool;
        default = if osConfig != null then osConfig.dotfiles.security.onepasswordGui.enable else false;
        defaultText = lib.literalExpression "osConfig.dotfiles.security.onepasswordGui.enable, or false without osConfig";
        description = "Whether to enable 1Password SSH signing (op-ssh-sign) on Linux.";
      };

      identity = {
        name = lib.mkOption {
          type = lib.types.str;
          default = "Wenxuan Shi";
          description = "Author name for git and jj commits.";
        };
        email = lib.mkOption {
          type = lib.types.str;
          default = "whexy@outlook.com";
          description = "Author email for git and jj commits.";
        };
      };

      signing.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to sign commits and tags with the owner's SSH key, which needs an SSH agent holding it.";
      };
    };
  };

  imports = [
    ./git.nix
    ./git-signing.nix
  ];

  config = lib.mkIf (config.dotfiles.vcs.git.command.enable && pkgs.stdenv.hostPlatform.isLinux) {
    home.packages = [ pkgs.git ];
  };
}
