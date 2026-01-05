return {
	{
		-- jump to next reference
		"mawkler/refjump.nvim",
		event = "LspAttach",
		opts = {
			keymaps = {
				next = "]]",
				prev = "[[",
			},
		},
	},

	{
		-- use "s" to jump to keywords
		"folke/flash.nvim",
		event = "VeryLazy",
		opts = {},
		keys = {
			{
				"s",
				mode = { "n", "x", "o" },
				function()
					require("flash").jump()
				end,
				desc = "Flash",
			},
			{
				"S",
				mode = { "n", "x", "o" },
				function()
					require("flash").treesitter()
				end,
				desc = "Flash Treesitter",
			},
		},
	},

	{
		-- provide function / class context
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		event = "VeryLazy",
		dependencies = {
			"nvim-treesitter/nvim-treesitter",
		},

		opts = {
			move = {
				enable = true,
				set_jumps = true,
				keys = {
					goto_next_start = {
						["]f"] = "@function.outer",
						["]c"] = "@class.outer",
						["]a"] = "@parameter.inner",
					},
					goto_next_end = {
						["]F"] = "@function.outer",
						["]C"] = "@class.outer",
						["]A"] = "@parameter.inner",
					},
					goto_previous_start = {
						["[f"] = "@function.outer",
						["[c"] = "@class.outer",
						["[a"] = "@parameter.inner",
					},
					goto_previous_end = {
						["[F"] = "@function.outer",
						["[C"] = "@class.outer",
						["[A"] = "@parameter.inner",
					},
				},
			},
		},

		config = function(_, opts)
			local move = require("nvim-treesitter-textobjects.move")

			-- helper: check whether a language has textobjects queries
			local function has_textobjects(lang)
				local ok = pcall(vim.treesitter.query.get, lang, "textobjects")
				return ok and vim.treesitter.query.get(lang, "textobjects") ~= nil
			end

			-- attach movement keybindings to buffer
			local function attach(buf)
				local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
				if not lang or not has_textobjects(lang) then
					return -- don't attach if this language has no textobjects.scm
				end

				local moves = opts.move.keys or {}
				for method, keymaps in pairs(moves) do
					for key, query in pairs(keymaps) do
						vim.keymap.set({ "n", "x", "o" }, key, function()
							move[method](query, "textobjects")
						end, {
							buffer = buf,
							silent = true,
							desc = ("TS %s (%s)"):format(method, query),
						})
					end
				end
			end

			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("ts_textobjects_attach", { clear = true }),
				callback = function(ev)
					attach(ev.buf)
				end,
			})

			-- attach to existing buffers
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(buf) then
					attach(buf)
				end
			end
		end,
	},
}
