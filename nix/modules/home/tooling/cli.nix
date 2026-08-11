# Everyday CLI tools: file/process inspection, decompressors, and general
# utilities. Shared by all development presets.
{
  config,
  pkgs,
  lib,
  inputs,
  perSystem,
  ...
}:
{
  config = lib.mkIf config.dotfiles.tooling.cli.enable {
    home.packages =
      with pkgs;
      [
        age
        inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.agenix
        bzip2
        cloudflared
        duf
        dust
        fd
        file
        just
        kubectl
        lazygit
        lldb
        lsof
        ncdu
        nix-output-monitor
        p7zip
        perSystem.self.doordash-cli
        ripgrep
        tldr
        unrar
        xz
      ]
      ++ lib.optionals config.targets.genericLinux.enable [
        _1password-cli
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        # only available on macOS
        container
      ];
  };
}
