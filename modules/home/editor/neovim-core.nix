# Returns the Nixvim module (not a Home Manager module) with the editing
# basics every Neovim here shares, VS Code's included. `remapWindowKeys` makes
# the window keymaps recursive, so they reach mappings of <C-w> such as
# vscode-neovim's.
{
  remapWindowKeys ? false,
}:
let
  windowKeymap = key: action: desc: {
    mode = "n";
    inherit key action;
    options = {
      inherit desc;
    }
    // (if remapWindowKeys then { remap = true; } else { });
  };
in
{
  globals = {
    mapleader = " ";
    maplocalleader = ",";
  };

  opts = {
    ignorecase = true;
    smartcase = true;
  };

  autoCmd = [
    {
      event = [ "TextYankPost" ];
      callback.__raw = ''
        function()
          local event = vim.v.event
          if event.operator == "y" and event.regname == "" then
            vim.fn.setreg("+", event.regcontents, event.regtype)
          end
        end
      '';
    }
  ];

  keymaps = [
    {
      mode = "x";
      key = "<";
      action = "<gv";
    }
    {
      mode = "x";
      key = ">";
      action = ">gv";
    }
    (windowKeymap "<leader>-" "<C-W>s" "Split Window Below")
    (windowKeymap "<leader>|" "<C-W>v" "Split Window Right")
    (windowKeymap "<leader>wd" "<C-W>c" "Delete Window")
  ];
}
