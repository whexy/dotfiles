# Nixvim module (not a Home Manager module) with the text-editing plugins the
# development profile shares with VS Code's Neovim. They work on buffer text
# alone, so they behave the same under vscode-neovim.
{
  plugins = {
    treesitter.enable = true;
    treesitter-textobjects.enable = true;
    flash.enable = true;
    mini-ai = {
      enable = true;
      settings = {
        n_lines = 500;
        custom_textobjects.__raw = ''
          (function()
            local ai = require("mini.ai")
            return {
              o = ai.gen_spec.treesitter({
                a = { "@block.outer", "@conditional.outer", "@loop.outer" },
                i = { "@block.inner", "@conditional.inner", "@loop.inner" },
              }),
              f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
              c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
              t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" },
              d = { "%f[%d]%d+" },
              u = ai.gen_spec.function_call(),
              U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }),
            }
          end)()
        '';
      };
    };
    mini-surround = {
      enable = true;
      settings.mappings = {
        add = "gsa";
        delete = "gsd";
        find = "gsf";
        find_left = "gsF";
        highlight = "gsh";
        replace = "gsr";
        update_n_lines = "gsn";
      };
    };
  };

  keymaps = [
    {
      mode = [
        "n"
        "x"
        "o"
      ];
      key = "s";
      action.__raw = "function() require('flash').jump() end";
      options.desc = "Flash";
    }
    {
      mode = [
        "n"
        "x"
        "o"
      ];
      key = "S";
      action.__raw = "function() require('flash').treesitter() end";
      options.desc = "Flash Treesitter";
    }
  ];

  extraConfigLua = ''
    local ts_move = require("nvim-treesitter-textobjects.move")
    local ts_moves = {
      goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
      goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
      goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
      goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
    }
    for method, mappings in pairs(ts_moves) do
      for key, query in pairs(mappings) do
        vim.keymap.set({ "n", "x", "o" }, key, function() ts_move[method](query, "textobjects") end,
          { silent = true, desc = ("TS %s (%s)"):format(method, query) })
      end
    end
  '';
}
