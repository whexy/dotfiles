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
        ripgrep
        tldr
        unrar
        xz
      ]
      # Upstream ships prebuilt binaries for only some platforms.
      ++ lib.optionals (lib.meta.availableOn pkgs.stdenv.hostPlatform perSystem.self.doordash-cli) [
        perSystem.self.doordash-cli
      ]
      ++ lib.optionals config.targets.genericLinux.enable [
        _1password-cli
      ]
      # macOS ships caffeinate.
      ++ lib.optionals pkgs.stdenv.isLinux [
        perSystem.self.caffeinate
      ]
      ++ lib.optionals pkgs.stdenv.isDarwin [
        # only available on macOS
        container
      ];
  };
}
