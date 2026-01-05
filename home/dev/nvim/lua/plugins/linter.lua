local language_packages = require("language_packages")

return {
  {
    "mfussenegger/nvim-lint",
    event = "VeryLazy",
    config = function()
      local lint = require("lint")

      vim.api.nvim_create_autocmd({
        "BufWritePost",
        "BufReadPost",
        "InsertLeave",
      }, {
        group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
        callback = function()
          local ft = vim.bo.filetype

          for _, item in ipairs(language_packages.LINTERS) do
            if item.language == ft and item.name then
              lint.try_lint(item.name)
            end
          end
        end,
      })
    end,
  },
}
