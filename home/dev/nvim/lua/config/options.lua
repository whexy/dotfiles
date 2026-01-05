vim.g.mapleader = ","
vim.g.maplocalleader = ","

-- show the absolute line number for the current line
vim.opt.number = true
-- show relative line numbers
vim.opt.relativenumber = true

-- Confirm before quitting unsaved changes
vim.opt.confirm = true
-- Persistent undo across sessions
vim.opt.undofile = true
-- Practically infinite undo (safe)
vim.opt.undolevels = 1000000
-- Enable mouse in all modes
vim.opt.mouse = "a"

-- Use spaces instead of tabs
vim.opt.expandtab = true
-- Indent size
vim.opt.shiftwidth = 2
-- Tab character width
vim.opt.tabstop = 2
-- Round indent to nearest multiple of shiftwidth
vim.opt.shiftround = true
-- Auto-indent new lines intelligently
vim.opt.autoindent = true
vim.opt.smartindent = true

-- Keep comments, wrap text, autoformat when possible
vim.opt.formatoptions = "jcroqlnt"

-- Case-insensitive by default
vim.opt.ignorecase = true
-- But smart if uppercase is used
vim.opt.smartcase = true

-- Live preview for :substitute
vim.opt.inccommand = "nosplit"
vim.opt.grepprg = "rg --vimgrep" -- Use ripgrep for :grep
-- Match file:line:col:message format
vim.opt.grepformat = "%f:%l:%c:%m"

-- Highlight current line
vim.opt.cursorline = true
-- Always show sign column
vim.opt.signcolumn = "yes"
-- Show cursor position in statusline
vim.opt.ruler = true
-- Global statusline (once you add one)
vim.opt.laststatus = 3
-- Enable true colors
vim.opt.termguicolors = true
-- Prevent tiny splits
vim.opt.winminwidth = 5
-- Keep 4 lines visible around cursor
vim.opt.scrolloff = 4
-- Keep 8 columns visible horizontally
vim.opt.sidescrolloff = 8
-- Disable line wrapping
vim.opt.wrap = false
-- (If wrapping) break at words
vim.opt.linebreak = true
-- Show invisible characters (tabs, etc.)
vim.opt.list = false
vim.opt.showmode = false
vim.opt.colorcolumn = "80"

-- Fold by indentation level
vim.opt.foldmethod = "indent"
-- Start unfolded
vim.opt.foldlevel = 99
-- Simple fold indicator (first line + …)
vim.opt.foldtext = "v:lua.vim.fn.getline(v:foldstart) .. ' …'"

-- Restore view after jump
vim.opt.jumpoptions = "view"
-- Allow cursor past EOL in block mode
vim.opt.virtualedit = "block"
-- Enhanced command completion
vim.opt.wildmode = "longest:full,full"
-- Horizontal splits below
vim.opt.splitbelow = true
-- Vertical splits to the right
vim.opt.splitright = true
-- Preserve layout when splitting
vim.opt.splitkeep = "screen"
