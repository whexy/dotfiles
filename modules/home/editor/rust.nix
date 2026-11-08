# Rust: toolchain manager (rustup provides rust-analyzer and rustfmt).
{
  config,
  pkgs,
  lib,
  ...
}:
{
  config = import ./language.nix { inherit config lib; } "rust" {
    packages = with pkgs; [
      rustup
    ];
    textWidth = 100;
    grammars = [
      "ron"
      "rust"
    ];
    nixvim = {
      plugins = {
        rustaceanvim = {
          enable = true;
          settings.server = {
            on_attach.__raw = ''
              function(_, bufnr)
                vim.keymap.set("n", "<leader>cR", function() vim.cmd.RustLsp("codeAction") end,
                  { buffer = bufnr, desc = "Code Action" })
                vim.keymap.set("n", "<leader>dr", function() vim.cmd.RustLsp("debuggables") end,
                  { buffer = bufnr, desc = "Rust Debuggables" })
              end
            '';
            default_settings.rust-analyzer = {
              cargo = {
                allFeatures = true;
                loadOutDirsFromCheck = true;
                buildScripts.enable = true;
              };
              checkOnSave = true;
              diagnostics.enable = true;
              procMacro.enable = true;
              files = {
                exclude = [
                  ".direnv"
                  ".git"
                  ".jj"
                  ".github"
                  ".gitlab"
                  "bin"
                  "node_modules"
                  "target"
                  "venv"
                  ".venv"
                ];
                watcher = "client";
              };
            };
          };
        };
        crates = {
          enable = true;
          settings = {
            lsp = {
              enabled = true;
              actions = true;
              completion = true;
              hover = true;
            };
            completion.crates = {
              enabled = true;
              max_results = 8;
              min_chars = 3;
            };
          };
        };
        conform-nvim.settings.formatters_by_ft.rust = [ "rustfmt" ];
      };
    };
  };
}
