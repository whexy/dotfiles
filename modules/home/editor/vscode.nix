# VS Code as a Neovim front end. Settings and extensions are read-only store
# paths, so this module is their only source and the extensions listed here
# are the only ones VS Code can load.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  platform = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "linux";
in
{
  config = lib.mkIf config.dotfiles.editor.vscode.enable {
    programs.vscode = {
      enable = true;
      mutableExtensionsDir = false;
      profiles.default = {
        enableUpdateCheck = false;
        enableExtensionUpdateCheck = false;
        # Remote-SSH's extension pack (its config-file editing and Remote
        # Explorer) is listed too: VS Code cannot install it into the
        # read-only extensions directory.
        extensions = with pkgs.vscode-extensions; [
          asvetliakov.vscode-neovim
          ms-vscode-remote.remote-ssh
          ms-vscode-remote.remote-ssh-edit
          ms-vscode.remote-explorer
        ];
        userSettings = {
          # Copilot ships built in; these hide its chat, its sign-in prompts,
          # the first-run sign-in modal, and the secondary side bar that would
          # open empty without the chat.
          "chat.disableAIFeatures" = true;
          "workbench.welcomePage.experimentalOnboarding" = false;
          "workbench.secondarySideBar.defaultVisibility" = "hidden";
          "telemetry.telemetryLevel" = "off";
          "extensions.ignoreRecommendations" = true;
          "editor.lineNumbers" = "relative";

          # Plain Neovim rather than the Nixvim build, whose baked-in init
          # starts LSP, completion, and UI plugins that duplicate VS Code.
          "vscode-neovim.neovimExecutablePaths.${platform}" = lib.getExe pkgs.neovim-unwrapped;
          "vscode-neovim.neovimInitVimPaths.${platform}" = "${./vscode-neovim.lua}";
          # vscode-neovim does not declare Restricted Mode support, so VS Code
          # would disable it in every folder not yet trusted.
          "extensions.supportUntrustedWorkspaces"."asvetliakov.vscode-neovim".supported = true;
          # Its own extension host keeps Neovim's input handling from waiting
          # behind other extensions.
          "extensions.experimental.affinity"."asvetliakov.vscode-neovim" = 1;
        };
      };
    };
  };
}
