# Shell configuration
args@{
  config,
  pkgs,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.shell;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
{
  config = lib.mkIf cfg.zsh.enable (
    let
      ghostty-pkg = if isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
    in
    {
      programs.zsh = {
        enable = true;
        enableCompletion = true;

        # Tailscale SSH command sessions can register with logind without
        # exporting its runtime directory. Reuse it only if logind has already
        # provisioned a private directory for this user; never create one here.
        envExtra = lib.mkIf pkgs.stdenv.hostPlatform.isLinux ''
          if [[ -z "''${XDG_RUNTIME_DIR:-}" ]]; then
            if [[ -d "/run/user/$EUID" && ! -L "/run/user/$EUID" \
                  && -O "/run/user/$EUID" \
                  && "$(${pkgs.coreutils}/bin/stat -c %a -- "/run/user/$EUID" 2>/dev/null)" == 700 ]]; then
              export XDG_RUNTIME_DIR="/run/user/$EUID"
            fi
          fi
        '';

        # Upstream dumps to $ZDOTDIR/.zcompdump; keep it out of $HOME. Unused when
        # oh-my-zsh is enabled, which runs its own compinit (see zsh-extras.nix).
        completionInit = ''
          zcompdump_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
          [[ -d $zcompdump_dir ]] || mkdir -p $zcompdump_dir
          autoload -U compinit && compinit -d "$zcompdump_dir/zcompdump-$ZSH_VERSION"
          unset zcompdump_dir
        '';

        history = {
          save = 10000;
          size = 10000;
          share = true;
        };

        initContent = lib.mkMerge [
          # On non-NixOS Linux the login shell is the distro's /bin/zsh. We avoid
          # `chsh`-ing to the nix-managed zsh since gc/rename would break it, so
          # instead re-exec into it from the distro zsh's .zshrc.
          (lib.mkIf config.targets.genericLinux.enable (
            let
              targetShellBin =
                if cfg.default == "nushell" then "${pkgs.nushell}/bin/nu" else "${pkgs.zsh}/bin/zsh";
            in
            lib.mkOrder 100 ''
              # Re-exec into the nix-managed shell once, before any output.
              # Guard against re-exec loops (the same .zshrc is sourced by both shells).
              if [[ -z "$IN_NIX_SHELL" && "''${SHELL:-}" != "${targetShellBin}" \
                    && -x "${targetShellBin}" ]]; then
                export IN_NIX_SHELL=1
                export SHELL="${targetShellBin}"
                exec "${targetShellBin}" -l
              fi
            ''
          ))

          # Manually trigger ghostty integration (only when running inside Ghostty)
          ''
            if [[ "$TERM" == "xterm-ghostty" ]]; then
              source "${ghostty-pkg.shell_integration}/zsh/ghostty-integration"
            fi
          ''
        ];
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
  );
}
