# Alfred's workflows (macOS). The system desktop group installs the app; a
# feature adds its own workflow to `dotfiles.launcher.alfred.workflows`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.launcher.alfred;
  # Alfred reads workflows from here unless Preferences → Advanced sets a sync
  # folder; with one set, these links go unread.
  workflowsDir = "Library/Application Support/Alfred/Alfred.alfredpreferences/workflows";
in
{
  config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isDarwin) {
    # Each workflow is linked whole, so Alfred Preferences cannot edit it:
    # change it here instead.
    home.file = lib.mapAttrs' (
      name: source: lib.nameValuePair "${workflowsDir}/user.workflow.dotfiles-${name}" { inherit source; }
    ) cfg.workflows;
  };
}
