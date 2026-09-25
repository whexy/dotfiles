# The home baked into packages/sandbox-image, a workspace for AI agents. Its
# files are linked into the image at build time and activation never runs:
# the sandbox has no root and no service manager.
{
  inputs,
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.self.homeModules.all
  ]
  ++ inputs.self.lib.homeCapsModules [
    "base"
    "dev-lite"
  ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.self.lib.overlays.unstable
    inputs.self.lib.overlays.llm-tools
  ];

  # Agents edit files directly, so no editor or its language bundles.
  dotfiles.editor =
    lib.genAttrs
      [
        "neovim"
        "config"
        "markdown"
        "nix"
        "python"
        "shell"
        "typst"
      ]
      (_: {
        enable = lib.mkForce false;
      });

  # Both only take effect through activation or a user service manager.
  dotfiles.nix.ghTokenFlakes.enable = lib.mkForce false;
  services.gpg-agent.enable = lib.mkForce false;
  nix.gc.automatic = lib.mkForce false;

  # Agents fetch missing tools with `nix run`, using a single-user store the
  # sandbox user owns. The runner drops every capability, so builds cannot
  # create the namespaces the Nix sandbox needs.
  nix.settings.sandbox = false;

  # What n8n expects from the upstream sandbox image: Node >= 24 for
  # @n8n/workflow-sdk, tsc, and a compiler with Python headers for source
  # builds, since the sandbox cannot install one later.
  home.packages = with pkgs; [
    config.nix.package
    nodejs_24
    unstable.typescript
    python3
    gcc
    gnumake
    ripgrep
  ];
}
