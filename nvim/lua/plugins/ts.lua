local language_config = require("language_packages")

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		event = "VeryLazy",
		build = ":TSUpdate",
		config = function()
			local ts = require("nvim-treesitter")
			ts.setup({
				install_dir = vim.fn.stdpath("data") .. "/site",
			})

			-- install missing parsers
			local installed = {}
			for _, lang in ipairs(ts.get_installed()) do
				installed[lang] = true
			end

			local missing = {}
			for _, lang in ipairs(language_config.TS_PACKAGES) do
				if not installed[lang] then
					table.insert(missing, lang)
				end
			end

			if #missing > 0 then
				ts.install(missing, { summary = true })
			end

			-- enable parser for file
			vim.api.nvim_create_autocmd("FileType", {

				callback = function(ev)
					local bufnr = ev.buf

					-- Highlight
					pcall(vim.treesitter.start, bufnr)

					-- indent
					vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"

					-- folding
					vim.wo.foldmethod = "expr"
					vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
				end,
			})
		end,
	},
}
