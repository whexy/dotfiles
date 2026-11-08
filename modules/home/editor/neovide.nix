# Neovide GUI configuration (mirrors Ghostty's look & feel)
args@{
  config,
  lib,
  pkgs,
  ...
}:
let
  osConfig = args.osConfig or null;
  cfg = config.dotfiles.editor;
  style = import ../terminal/style.nix;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.neovide.enable (
      let
        macbookScreen = osConfig.dotfiles.hardware.display.macbookScreen or false;
      in
      {
        programs.neovide = {
          enable = true;
          settings = {
            font = {
              normal = [ style.font ];
              # Neovide's font size is a float.
              size = 0.0 + style.fontSize macbookScreen;
            };
            transparency = style.opacity;
          }
          # Same as Ghostty's background-blur; Neovide only supports blur on macOS
          // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin { background-blur-radius = 20; };
        };
      }
    ))

    # Neovide also attaches to Neovim on other machines (`neovide --server`),
    # so the development profile has its paste keys whether or not this home
    # runs Neovide.
    (lib.mkIf (cfg.neovim.enable && (cfg.neovide.enable || cfg.neovim.dev)) {
      programs.nixvim.extraConfigLua = ''
        if vim.g.neovide then
          local paste = vim.fn.has("mac") == 1 and "<D-v>" or "<C-S-v>"
          vim.keymap.set("n", paste, '"+p', { desc = "Paste from system clipboard" })
          vim.keymap.set("v", paste, '"+p', { desc = "Paste from system clipboard" })
          vim.keymap.set("i", paste, "<C-r>+", { desc = "Paste from system clipboard" })
        end
      '';
    })
  ];
}
