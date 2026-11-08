# VCS group: git and git-adjacent tools.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.dotfiles.vcs = {
    git = {
      enable = lib.mkEnableOption "git";
      command.enable = lib.mkEnableOption ''
        the git command on Linux, also in homes where `git.enable` does not
        configure git. macOS keeps Apple's git, which avoids a keychain
        prompt
      '';
      opSshSigning = lib.mkEnableOption "1Password SSH signing (op-ssh-sign) on Linux";

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
