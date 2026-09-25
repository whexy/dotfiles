# The home baked into packages/sandbox-image, a workspace for AI agents. Its
# files are linked into the image at build time and activation never runs:
# the sandbox has no root and no service manager.
{
  inputs,
  config,
  ...
}:
{
  imports = [
    inputs.self.homeModules.all
  ]
  ++ inputs.self.lib.homeCapsModules [ "agent" ];

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [ inputs.self.lib.overlays.unstable ];

  # Agents fetch missing tools with `nix run`, using a single-user store the
  # sandbox user owns. The runner drops every capability, so builds cannot
  # create the namespaces the Nix sandbox needs.
  nix.settings.sandbox = false;

  # The environment card: what an agent cannot discover by running commands.
  home.file."AGENTS.md".source = ./AGENTS.md;

  # The image has no system Nix, so the CLI comes from the home.
  home.packages = [ config.nix.package ];
}
