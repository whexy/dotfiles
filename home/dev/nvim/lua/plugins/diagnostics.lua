return {
	{
		"rachartier/tiny-inline-diagnostic.nvim",
		event = "VeryLazy",
		opts = {
			preset = "minimal",
			options = {
				overwrite_events = { "LspAttach", "DiagnosticChanged" },
			},
		},
		config = function(_, opts)
			require("tiny-inline-diagnostic").setup(opts)
			-- Disable Neovim's default virtual text
			vim.diagnostic.config({ virtual_text = false })
		end,
	},
}
