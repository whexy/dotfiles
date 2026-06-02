# Shell configuration
{
  config,
  pkgs,
  lib,
  ...
}:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    history = {
      save = 10000;
      size = 10000;
      share = true;
    };

    # On non-NixOS Linux the login shell is the distro's /bin/zsh. We avoid
    # `chsh`-ing to the nix-managed zsh since gc/rename would break it, so
    # instead re-exec into it from the distro zsh's .zshrc.
    initContent = lib.mkIf config.targets.genericLinux.enable (
      lib.mkOrder 100 ''
        # Re-exec into the nix-managed zsh once, before any output.
        # Guard against re-exec loops (the same .zshrc is sourced by both shells).
        if [[ -z "$IN_NIX_ZSH" && "''${SHELL:-}" != "${pkgs.zsh}/bin/zsh" \
              && -x "${pkgs.zsh}/bin/zsh" ]]; then
          export IN_NIX_ZSH=1
          export SHELL="${pkgs.zsh}/bin/zsh"
          exec "${pkgs.zsh}/bin/zsh" -l
        fi
      ''
    );
  };

  programs.ssh = lib.mkDefault {
    enable = true;
    enableDefaultConfig = false;
    # HM 26.05 deprecated `matchBlocks`; entries now live under `settings`
    # using OpenSSH directive names directly (no `extraOptions` wrapper).
    settings = {
      "*" = {
        AddKeysToAgent = "yes";
      };
    };
  };
}
