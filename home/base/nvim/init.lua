-- Minimal Neovim Configuration for Base Capability
-- A comfortable, plugin-free setup with essential features

-- Leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- Line numbers
vim.opt.number = true
vim.opt.relativenumber = true

-- Persistence
vim.opt.confirm = true
vim.opt.undofile = true
vim.opt.undolevels = 1000000

-- Mouse & clipboard
vim.opt.mouse = "a"

-- Indentation
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.shiftround = true
vim.opt.autoindent = true
vim.opt.smartindent = true

-- Formatting
vim.opt.formatoptions = "jcroqlnt"

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.inccommand = "nosplit"
vim.opt.grepprg = "rg --vimgrep"
vim.opt.grepformat = "%f:%l:%c:%m"

-- UI
vim.opt.cursorline = true
vim.opt.signcolumn = "yes"
vim.opt.ruler = true
vim.opt.laststatus = 2
vim.opt.termguicolors = true
vim.opt.showmode = false

-- Scrolling & windows
vim.opt.scrolloff = 4
vim.opt.sidescrolloff = 8
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.splitkeep = "screen"

-- Wrapping & display
vim.opt.wrap = false
vim.opt.linebreak = true

-- Folding
vim.opt.foldmethod = "indent"
vim.opt.foldlevel = 99

-- Misc
vim.opt.virtualedit = "block"
vim.opt.wildmode = "longest:full,full"

-- OSC52 clipboard integration
local function paste_from_unnamed()
	local lines = vim.split(vim.fn.getreg(""), "\n", { plain = true })
	return { #lines > 0 and lines or { "" }, vim.fn.getregtype(""):sub(1, 1) }
end

vim.g.clipboard = {
	name = "OSC 52",
	copy = {
		["+"] = require("vim.ui.clipboard.osc52").copy("+"),
		["*"] = require("vim.ui.clipboard.osc52").copy("*"),
	},
	paste = {
		["+"] = paste_from_unnamed,
		["*"] = paste_from_unnamed,
	},
}

vim.api.nvim_create_autocmd("TextYankPost", {
	callback = function()
		local ev = vim.v.event
		if ev.operator == "y" and ev.regname == "" then
			vim.fn.setreg("+", ev.regcontents, ev.regtype)
		end
	end,
})

-- Keymaps
local map = vim.keymap.set

-- Better up/down on wrapped lines
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

-- Window navigation
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to below window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to above window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- Clear search highlight on escape
map({ "i", "n", "s" }, "<esc>", function()
	vim.cmd("noh")
	return "<esc>"
end, { expr = true, desc = "Escape and Clear hlsearch" })

-- Save file
map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save File" })

-- Stay in visual mode after indent
map("x", "<", "<gv")
map("x", ">", ">gv")

-- Window splits
map("n", "<leader>-", "<C-W>s", { desc = "Split Window Below" })
map("n", "<leader>|", "<C-W>v", { desc = "Split Window Right" })
map("n", "<leader>wd", "<C-W>c", { desc = "Delete Window" })
