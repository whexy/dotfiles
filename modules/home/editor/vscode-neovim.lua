-- Neovim init for vscode-neovim. VS Code owns the UI, language features, and
-- completion, so this keeps only the editing behavior of the Nixvim profile.
vim.g.mapleader = " "
vim.g.maplocalleader = ","

vim.o.ignorecase = true
vim.o.smartcase = true

-- Neovim's own provider needs wl-copy or pbcopy on the extension host's PATH;
-- VS Code's clipboard API works everywhere VS Code runs.
vim.g.clipboard = vim.g.vscode_clipboard

vim.api.nvim_create_autocmd("TextYankPost", {
	callback = function()
		local event = vim.v.event
		if event.operator == "y" and event.regname == "" then
			vim.fn.setreg("+", event.regcontents, event.regtype)
		end
	end,
})

vim.keymap.set("n", "<esc>", "<cmd>noh<cr><esc>", { desc = "Escape and Clear hlsearch" })
vim.keymap.set("x", "<", "<gv")
vim.keymap.set("x", ">", ">gv")

-- Recursive, so they reach vscode-neovim's <C-w> mappings to editor groups.
vim.keymap.set("n", "<leader>-", "<C-w>s", { remap = true, desc = "Split Window Below" })
vim.keymap.set("n", "<leader>|", "<C-w>v", { remap = true, desc = "Split Window Right" })
vim.keymap.set("n", "<leader>wd", "<C-w>c", { remap = true, desc = "Delete Window" })
