# Git configuration
{
  home-manager.users.whexy =
    { pkgs, lib, ... }:
    let
      # Wrap gh with 1Password to inject GitHub token
      gh-wrapped = pkgs.mkOpWrapped pkgs.gh [ "gh" ] {
        "GH_TOKEN" = "op://Developer/GitHub Personal Access Token/token";
      };
    in
    {
      home.packages = [ gh-wrapped ];

      programs.git = {
        enable = true;
        package = pkgs.git.override { osxkeychainSupport = false; };

        signing = {
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIcI4E3boeSWD5+eb9K6Zotw7dxjjvHP60tBjoM0uYn";
          signByDefault = true;
        };

        settings = {
          user = {
            name = "Wenxuan Shi";
            email = "whexy@outlook.com";
          };

          gpg = {
            format = "ssh";
            ssh = {
              allowedSignersFile = "~/.git_allowed_signers";
              program = lib.mkIf pkgs.stdenv.isDarwin "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
            };
          };

          credential = {
            "https://github.com" = {
              helper = "!${gh-wrapped}/bin/gh auth git-credential";
            };
            "https://gist.github.com" = {
              helper = "!${gh-wrapped}/bin/gh auth git-credential";
            };
          };
        };
      };

      programs.delta = {
        enable = true;
        enableGitIntegration = true;
        options = {
          line-numbers = true;
          side-by-side = true;
        };
      };

      home.file.".git_allowed_signers".text = ''
        whexy@outlook.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIcI4E3boeSWD5+eb9K6Zotw7dxjjvHP60tBjoM0uYn
      '';
    };
}
