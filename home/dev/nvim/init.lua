-- Neovim Configuration (Single File) - vim.pack API (Neovim 0.12+)
-- Run after install: :TSUpdate, :call firenvim#install(0)

-- ╭──────────────────────────────────────────────────────────────────────╮
-- │                         LANGUAGE CONFIG                              │
-- ╰──────────────────────────────────────────────────────────────────────╯

local TS_PACKAGES = {
	"bash",
	"cpp",
	"go",
	"gomod",
	"gosum",
	"gowork",
	"haskell",
	"javascript",
	"json5",
	"lua",
	"ninja",
	"nix",
	"python",
	"regex",
	"ron",
	"rst",
	"rust",
	"typescript",
	"typst",
	"yaml",
	"zig",
}

local LSPS = {
	"basedpyright",
	"clangd",
	"gopls",
	"hls",
	"jsonls",
	"lua_ls",
	"nixd",
	"ruff",
	"tinymist",
	"tombi",
	"ts_ls",
	"yaml-language-server",
	"zls",
}

local FORMATTERS = {
	haskell = { "ormolu" },
	html = { "prettier" },
	json = { "prettier" },
	lua = { "stylua" },
	nix = { "nixfmt" },
	python = { "ruff" },
	rust = { "rustfmt" },
	sh = { "shfmt" },
	toml = { "tombi" },
	typst = { "typstyle" },
	yaml = { "yamlfmt" },
}

local LINTERS = {
	go = { "golangcilint" },
	haskell = { "hlint" },
	sh = { "shellcheck" },
	toml = { "tombi" },
}

-- ╭──────────────────────────────────────────────────────────────────────╮
-- │                              OPTIONS                                 │
-- ╰──────────────────────────────────────────────────────────────────────╯

-- Leader keys
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- Local settings
vim.opt.exrc = true
vim.opt.secure = true

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
vim.opt.laststatus = 3
vim.opt.termguicolors = true
vim.opt.colorcolumn = "80"
vim.opt.showmode = false

-- Scrolling & windows
vim.opt.winminwidth = 5
vim.opt.scrolloff = 4
vim.opt.sidescrolloff = 8
vim.opt.splitbelow = true
vim.opt.splitright = true
vim.opt.splitkeep = "screen"

-- Wrapping & display
vim.opt.wrap = false
vim.opt.linebreak = true
vim.opt.list = false

-- Folding
vim.opt.foldmethod = "indent"
vim.opt.foldlevel = 99
vim.opt.foldtext = "v:lua.vim.fn.getline(v:foldstart) .. ' ...'"

-- Misc
vim.opt.jumpoptions = "view"
vim.opt.virtualedit = "block"
vim.opt.wildmode = "longest:full,full"

-- ╭──────────────────────────────────────────────────────────────────────╮
-- │                              PLUGINS                                 │
-- ╰──────────────────────────────────────────────────────────────────────╯

vim.pack.add({
	-- Colorscheme
	"https://github.com/ellisonleao/gruvbox.nvim",

	-- UI components
	"https://github.com/MunifTanjim/nui.nvim",
	"https://github.com/nvim-tree/nvim-web-devicons",
	"https://github.com/nvim-lualine/lualine.nvim",
	"https://github.com/akinsho/bufferline.nvim",

	-- File explorer
	"https://github.com/nvim-lua/plenary.nvim",
	"https://github.com/antosha417/nvim-lsp-file-operations",
	"https://github.com/nvim-neo-tree/neo-tree.nvim",

	-- Keybinding help
	"https://github.com/folke/which-key.nvim",

	-- Completion
	"https://github.com/rafamadriz/friendly-snippets",
	"https://github.com/saghen/blink.cmp",

	-- Treesitter
	"https://github.com/nvim-treesitter/nvim-treesitter",
	{ src = "https://github.com/nvim-treesitter/nvim-treesitter-textobjects", version = "main" },

	-- Fuzzy finder
	"https://github.com/nvim-telescope/telescope.nvim",

	-- Navigation & motions
	"https://github.com/folke/flash.nvim",
	"https://github.com/mawkler/refjump.nvim",

	-- Text objects & editing
	"https://github.com/echasnovski/mini.ai",
	"https://github.com/echasnovski/mini.surround",
	"https://github.com/gbprod/yanky.nvim",

	-- Visual guides
	"https://github.com/lukas-reineke/indent-blankline.nvim",
	"https://github.com/HiPhish/rainbow-delimiters.nvim",

	-- Formatting & linting
	"https://github.com/stevearc/conform.nvim",
	"https://github.com/mfussenegger/nvim-lint",

	-- LSP & diagnostics
	"https://github.com/rachartier/tiny-code-action.nvim",
	"https://github.com/rachartier/tiny-inline-diagnostic.nvim",
	"https://github.com/neovim/nvim-lspconfig",

	-- Language-specific
	"https://github.com/mrcjkb/rustaceanvim",
	"https://github.com/saecki/crates.nvim",
	"https://github.com/chomosuke/typst-preview.nvim",

	-- Browser integration
	"https://github.com/glacambre/firenvim",
})

-- ╭──────────────────────────────────────────────────────────────────────╮
-- │                          PLUGIN CONFIG                               │
-- ╰──────────────────────────────────────────────────────────────────────╯

-- ── Colorscheme ──────────────────────────────────────────────────────────
vim.cmd.colorscheme("gruvbox")

-- ── Lualine ──────────────────────────────────────────────────────────────
require("lualine").setup()

-- ── Bufferline ───────────────────────────────────────────────────────────
local function buf_delete(bufnr)
	vim.cmd("bdelete " .. bufnr)
end

require("bufferline").setup({
	options = {
		close_command = buf_delete,
		right_mouse_command = buf_delete,
		diagnostics = "nvim_lsp",
		always_show_bufferline = true,
		diagnostics_indicator = function(_, _, diag)
			local icons = { Error = " ", Warn = " ", Hint = " ", Info = " " }
			local ret = (diag.error and icons.Error .. diag.error .. " " or "")
				.. (diag.warning and icons.Warn .. diag.warning or "")
			return vim.trim(ret)
		end,
		offsets = {
			{ filetype = "neo-tree", text = "Neo-tree", highlight = "Directory", text_align = "left" },
		},
		get_element_icon = function(opts)
			local ok, devicons = pcall(require, "nvim-web-devicons")
			return ok and devicons.get_icon_by_filetype(opts.filetype) or ""
		end,
	},
})

-- ── Neo-tree ─────────────────────────────────────────────────────────────
require("neo-tree").setup({
	source_selector = { winbar = true },
	filesystem = {
		follow_current_file = { enabled = true },
		filtered_items = { visible = true },
		use_libuv_file_watcher = true,
	},
})

-- ── Blink Completion ─────────────────────────────────────────────────────
require("blink.cmp").setup({
	keymap = { preset = "enter" },
	appearance = { nerd_font_variant = "mono" },
	completion = { documentation = { auto_show = false } },
	sources = { default = { "lsp", "path", "snippets", "buffer" } },
	fuzzy = { implementation = "lua" },
})

-- ── Treesitter ───────────────────────────────────────────────────────────
local ts = require("nvim-treesitter")
ts.setup({ install_dir = vim.fn.stdpath("data") .. "/site" })

-- Auto-install missing parsers
local installed = {}
for _, lang in ipairs(ts.get_installed()) do
	installed[lang] = true
end
local missing = vim.tbl_filter(function(l)
	return not installed[l]
end, TS_PACKAGES)
if #missing > 0 then
	ts.install(missing, { summary = true })
end

-- Treesitter textobjects movement
local function has_textobjects(lang)
	local ok, query = pcall(vim.treesitter.query.get, lang, "textobjects")
	return ok and query ~= nil
end

local ts_move_ok, ts_move = pcall(require, "nvim-treesitter-textobjects.move")
local ts_move_keys = {
	goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer", ["]a"] = "@parameter.inner" },
	goto_next_end = { ["]F"] = "@function.outer", ["]C"] = "@class.outer", ["]A"] = "@parameter.inner" },
	goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer", ["[a"] = "@parameter.inner" },
	goto_previous_end = { ["[F"] = "@function.outer", ["[C"] = "@class.outer", ["[A"] = "@parameter.inner" },
}

vim.api.nvim_create_autocmd("FileType", {
	group = vim.api.nvim_create_augroup("treesitter_setup", { clear = true }),
	callback = function(ev)
		local bufnr = ev.buf
		pcall(vim.treesitter.start, bufnr)
		vim.bo[bufnr].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		vim.wo.foldmethod = "expr"
		vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"

		local lang = vim.treesitter.language.get_lang(vim.bo[bufnr].filetype)
		if ts_move_ok and lang and has_textobjects(lang) then
			for method, keymaps in pairs(ts_move_keys) do
				for key, query in pairs(keymaps) do
					vim.keymap.set({ "n", "x", "o" }, key, function()
						ts_move[method](query, "textobjects")
					end, { buffer = bufnr, silent = true, desc = ("TS %s (%s)"):format(method, query) })
				end
			end
		end
	end,
})

-- ── Mini.ai (text objects) ───────────────────────────────────────────────
local ai = require("mini.ai")
ai.setup({
	n_lines = 500,
	custom_textobjects = {
		o = ai.gen_spec.treesitter({
			a = { "@block.outer", "@conditional.outer", "@loop.outer" },
			i = { "@block.inner", "@conditional.inner", "@loop.inner" },
		}),
		f = ai.gen_spec.treesitter({ a = "@function.outer", i = "@function.inner" }),
		c = ai.gen_spec.treesitter({ a = "@class.outer", i = "@class.inner" }),
		t = { "<([%p%w]-)%f[^<%w][^<>]->.-</%1>", "^<.->().*()</[^/]->$" }, -- HTML tags
		d = { "%f[%d]%d+" }, -- digits
		e = { -- word in camelCase/snake_case
			{ "%u[%l%d]+%f[^%l%d]", "%f[%S][%l%d]+%f[^%l%d]", "%f[%P][%l%d]+%f[^%l%d]", "^[%l%d]+%f[^%l%d]" },
			"^().*()$",
		},
		u = ai.gen_spec.function_call(), -- function call
		U = ai.gen_spec.function_call({ name_pattern = "[%w_]" }), -- function call (stricter)
	},
})

-- ── Mini.surround ────────────────────────────────────────────────────────
require("mini.surround").setup({
	mappings = {
		add = "gsa",
		delete = "gsd",
		find = "gsf",
		find_left = "gsF",
		highlight = "gsh",
		replace = "gsr",
		update_n_lines = "gsn",
	},
})

-- ── Yanky & OSC52 clipboard ──────────────────────────────────────────────
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

require("yanky").setup({ system_clipboard = { sync_with_ring = false } })

-- ── Refjump ──────────────────────────────────────────────────────────────
require("refjump").setup({
	keymaps = { next = "]]", prev = "[[" },
})

-- ── Indent Blankline ─────────────────────────────────────────────────────
require("ibl").setup({
	indent = { char = "|", tab_char = "|" },
	scope = { show_start = false, show_end = false },
	exclude = { filetypes = { "help", "lazy", "mason" } },
})

-- ── Conform (formatting) ─────────────────────────────────────────────────
require("conform").setup({
	format_on_save = { lsp_fallback = true, timeout_ms = 500 },
	formatters_by_ft = FORMATTERS,
})

-- ── Lint ─────────────────────────────────────────────────────────────────
local lint = require("lint")

vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
	group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
	callback = function()
		local ft = vim.bo.filetype
		if LINTERS[ft] then
			for _, linter in ipairs(LINTERS[ft]) do
				lint.try_lint(linter)
			end
		end
	end,
})

-- ── Tiny Inline Diagnostic ───────────────────────────────────────────────
require("tiny-inline-diagnostic").setup({
	preset = "minimal",
	options = { overwrite_events = { "LspAttach", "DiagnosticChanged" } },
})
vim.diagnostic.config({ virtual_text = false })

-- ── Rustaceanvim ─────────────────────────────────────────────────────────
vim.g.rustaceanvim = {
	server = {
		on_attach = function(_, bufnr)
			vim.keymap.set("n", "<leader>cR", function()
				vim.cmd.RustLsp("codeAction")
			end, { desc = "Code Action", buffer = bufnr })
			vim.keymap.set("n", "<leader>dr", function()
				vim.cmd.RustLsp("debuggables")
			end, { desc = "Rust Debuggables", buffer = bufnr })
		end,
		default_settings = {
			["rust-analyzer"] = {
				cargo = {
					allFeatures = true,
					loadOutDirsFromCheck = true,
					buildScripts = { enable = true },
				},
				checkOnSave = true,
				diagnostics = { enable = true },
				procMacro = { enable = true },
				files = {
					exclude = {
						".direnv",
						".git",
						".jj",
						".github",
						".gitlab",
						"bin",
						"node_modules",
						"target",
						"venv",
						".venv",
					},
					watcher = "client",
				},
			},
		},
	},
}

-- ── Crates.nvim ──────────────────────────────────────────────────────────
require("crates").setup({
	lsp = { enabled = true, actions = true, completion = true, hover = true },
	completion = { crates = { enabled = true, max_results = 8, min_chars = 3 } },
})

-- ── Typst Preview ────────────────────────────────────────────────────────
require("typst-preview").setup({ port = 19260 })

-- ── Firenvim ─────────────────────────────────────────────────────────────
vim.g.firenvim_config = {
	localSettings = {
		[".*"] = {
			takeover = "never",
			selector = [=[textarea:not([readonly],[aria-readonly]),div[role="textbox"],[contenteditable="true"]]=],
		},
	},
}

-- ╭──────────────────────────────────────────────────────────────────────╮
-- │                            LSP CONFIG                                │
-- ╰──────────────────────────────────────────────────────────────────────╯

-- Global LSP settings
vim.lsp.config("*", {
	capabilities = { textDocument = { semanticTokens = { multilineTokenSupport = true } } },
	root_markers = { ".git" },
})

-- ── Per-server configs ───────────────────────────────────────────────────

vim.lsp.config("lua_ls", {
	settings = {
		Lua = {
			runtime = { version = "LuaJIT" },
			diagnostics = { globals = { "vim" } },
			telemetry = { enable = false },
		},
	},
})

vim.lsp.config("tinymist", {
	settings = { formatterMode = "typstyle" },
})

vim.lsp.config("jsonls", {
	settings = {
		json = {
			format = { enable = true },
			validate = { enable = true },
		},
	},
})

vim.lsp.config("gopls", {
	settings = {
		gopls = {
			gofumpt = true,
			codelenses = {
				gc_details = false,
				generate = true,
				regenerate_cgo = true,
				run_govulncheck = true,
				test = true,
				tidy = true,
				upgrade_dependency = true,
				vendor = true,
			},
			hints = {
				assignVariableTypes = true,
				compositeLiteralFields = true,
				compositeLiteralTypes = true,
				constantValues = true,
				functionTypeParameters = true,
				parameterNames = true,
				rangeVariableTypes = true,
			},
			analyses = {
				nilness = true,
				unusedparams = true,
				unusedwrite = true,
				useany = true,
			},
			usePlaceholders = true,
			completeUnimported = true,
			staticcheck = true,
			directoryFilters = { "-.git", "-.vscode", "-.idea", "-.vscode-test", "-node_modules" },
			semanticTokens = true,
		},
	},
})

-- ── LSP attach handler ───────────────────────────────────────────────────

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("LspSetup", { clear = true }),
	callback = function(ev)
		local bufnr = ev.buf
		local client = vim.lsp.get_client_by_id(ev.data.client_id)

		-- Enable inlay hints if supported
		if client and client:supports_method("textDocument/inlayHint") then
			vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
		end

		-- Buffer-local keymaps
		local function map(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
		end

		map("n", "K", vim.lsp.buf.hover, "LSP Hover")
		map("n", "gd", vim.lsp.buf.definition, "Goto Definition")
		map("n", "gD", vim.lsp.buf.declaration, "Goto Declaration")
		map("n", "gr", vim.lsp.buf.references, "List References")
		map("n", "gi", vim.lsp.buf.implementation, "Goto Implementation")
		map("n", "gt", vim.lsp.buf.type_definition, "Type Definition")
		map("n", "<leader>cr", vim.lsp.buf.rename, "Rename Symbol")
		map("i", "<C-k>", vim.lsp.buf.signature_help, "Signature Help")
	end,
})

-- Enable all LSP servers
for _, lsp in ipairs(LSPS) do
	vim.lsp.enable(lsp)
end

-- ╭──────────────────────────────────────────────────────────────────────╮
-- │                             KEYMAPS                                  │
-- ╰──────────────────────────────────────────────────────────────────────╯

local map = vim.keymap.set

-- ── Navigation ───────────────────────────────────────────────────────────

-- Better up/down on wrapped lines
map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
map({ "n", "x" }, "<Down>", "v:count == 0 ? 'gj' : 'j'", { desc = "Down", expr = true, silent = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })
map({ "n", "x" }, "<Up>", "v:count == 0 ? 'gk' : 'k'", { desc = "Up", expr = true, silent = true })

-- Move lines up/down
map("n", "<A-j>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move Down" })
map("n", "<A-k>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move Up" })
map("i", "<A-j>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move Down" })
map("i", "<A-k>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move Up" })
map("v", "<A-j>", ":<C-u>execute \"'<,'>move '>+\" . v:count1<cr>gv=gv", { desc = "Move Down" })
map("v", "<A-k>", ":<C-u>execute \"'<,'>move '<-\" . (v:count1 + 1)<cr>gv=gv", { desc = "Move Up" })

-- Window navigation
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to below window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to above window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- ── Buffers ──────────────────────────────────────────────────────────────

map("n", "<S-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
map("n", "<S-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })

map("n", "<leader>bd", function()
	local cur, alt = vim.api.nvim_get_current_buf(), vim.fn.bufnr("#")
	vim.cmd(alt > 0 and vim.api.nvim_buf_is_loaded(alt) and "buffer #" or "bnext")
	vim.cmd("bdelete " .. cur)
end, { desc = "Delete Buffer" })

map("n", "<leader>bo", function()
	local current = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and buf ~= current then
			vim.cmd("bdelete " .. buf)
		end
	end
end, { desc = "Delete Other Buffers" })

map("n", "<leader>bD", "<cmd>bd<cr>", { desc = "Delete Buffer and Window" })
map("n", "<leader>bp", "<cmd>BufferLineTogglePin<cr>", { desc = "Toggle Pin" })
map("n", "<leader>bP", "<cmd>BufferLineGroupClose ungrouped<cr>", { desc = "Delete Non-Pinned Buffers" })

-- ── Search ───────────────────────────────────────────────────────────────

-- Clear search highlight on escape
map({ "i", "n", "s" }, "<esc>", function()
	vim.cmd("noh")
	return "<esc>"
end, { expr = true, desc = "Escape and Clear hlsearch" })

-- Better n/N (always search forward with n)
map("n", "n", "'Nn'[v:searchforward].'zv'", { expr = true, desc = "Next Search Result" })
map("x", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
map("o", "n", "'Nn'[v:searchforward]", { expr = true, desc = "Next Search Result" })
map("n", "N", "'nN'[v:searchforward].'zv'", { expr = true, desc = "Prev Search Result" })
map("x", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })
map("o", "N", "'nN'[v:searchforward]", { expr = true, desc = "Prev Search Result" })

-- ── Windows ──────────────────────────────────────────────────────────────

map("n", "<leader>-", "<C-W>s", { desc = "Split Window Below", remap = true })
map("n", "<leader>|", "<C-W>v", { desc = "Split Window Right", remap = true })
map("n", "<leader>wd", "<C-W>c", { desc = "Delete Window", remap = true })

-- ── Quickfix & Location List ─────────────────────────────────────────────

map("n", "<leader>xl", function()
	local ok, err = pcall(vim.fn.getloclist(0, { winid = 0 }).winid ~= 0 and vim.cmd.lclose or vim.cmd.lopen)
	if not ok and err then
		vim.notify(err, vim.log.levels.ERROR)
	end
end, { desc = "Location List" })

map("n", "<leader>xq", function()
	local ok, err = pcall(vim.fn.getqflist({ winid = 0 }).winid ~= 0 and vim.cmd.cclose or vim.cmd.copen)
	if not ok and err then
		vim.notify(err, vim.log.levels.ERROR)
	end
end, { desc = "Quickfix List" })

map("n", "[q", vim.cmd.cprev, { desc = "Previous Quickfix" })
map("n", "]q", vim.cmd.cnext, { desc = "Next Quickfix" })

-- ── Diagnostics ──────────────────────────────────────────────────────────

local function diagnostic_goto(next, severity)
	return function()
		vim.diagnostic.jump({
			count = (next and 1 or -1) * vim.v.count1,
			severity = severity and vim.diagnostic.severity[severity],
			float = true,
		})
	end
end

map("n", "<leader>cd", vim.diagnostic.open_float, { desc = "Line Diagnostics" })
map("n", "]d", diagnostic_goto(true), { desc = "Next Diagnostic" })
map("n", "[d", diagnostic_goto(false), { desc = "Prev Diagnostic" })
map("n", "]e", diagnostic_goto(true, "ERROR"), { desc = "Next Error" })
map("n", "[e", diagnostic_goto(false, "ERROR"), { desc = "Prev Error" })
map("n", "]w", diagnostic_goto(true, "WARN"), { desc = "Next Warning" })
map("n", "[w", diagnostic_goto(false, "WARN"), { desc = "Prev Warning" })

-- ── Telescope ────────────────────────────────────────────────────────────

map("n", "<leader><space>", "<cmd>Telescope find_files<cr>", { desc = "Find files" })
map("n", "<leader>/", "<cmd>Telescope live_grep<cr>", { desc = "Grep in files" })
map(
	"n",
	"<leader>,",
	"<cmd>Telescope buffers sort_mru=true sort_lastused=true ignore_current_buffer=true<cr>",
	{ desc = "Switch buffers" }
)
map("n", "<leader>:", "<cmd>Telescope command_history<cr>", { desc = "Command History" })

-- ── Flash ────────────────────────────────────────────────────────────────

map({ "n", "x", "o" }, "s", function()
	require("flash").jump()
end, { desc = "Flash" })

map({ "n", "x", "o" }, "S", function()
	require("flash").treesitter()
end, { desc = "Flash Treesitter" })

-- ── File Explorer ────────────────────────────────────────────────────────

map("n", "<leader>e", function()
	require("neo-tree.command").execute({ toggle = true, dir = vim.uv.cwd() })
end, { desc = "Explorer NeoTree (cwd)" })

-- ── Code Actions ─────────────────────────────────────────────────────────

map("n", "<leader>cf", function()
	require("conform").format({ async = true, lsp_fallback = true, timeout_ms = 500 })
end, { desc = "Format file" })

map("n", "<leader>ca", function()
	require("tiny-code-action").code_action()
end, { noremap = true, silent = true, desc = "Code Action" })

-- ── Misc ─────────────────────────────────────────────────────────────────

map({ "i", "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = "Save File" })
map("n", "<leader>K", "<cmd>norm! K<cr>", { desc = "Keywordprg" })
map("x", "<", "<gv") -- Stay in visual mode after indent
map("x", ">", ">gv")
map("n", "gco", "o<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", { desc = "Add Comment Below" })
map("n", "gcO", "O<esc>Vcx<esc><cmd>normal gcc<cr>fxa<bs>", { desc = "Add Comment Above" })
map("n", "<leader>fn", "<cmd>enew<cr>", { desc = "New File" })
map("n", "<leader>qq", "<cmd>qa<cr>", { desc = "Quit All" })
map("t", "<A-q>", "<C-\\><C-n>", { desc = "Escape terminal mode", remap = true })

map("n", "<leader>?", function()
	require("which-key").show({ global = false })
end, { desc = "Buffer Local Keymaps (which-key)" })

-- ╭──────────────────────────────────────────────────────────────────────╮
-- │                             COMMANDS                                 │
-- ╰──────────────────────────────────────────────────────────────────────╯

vim.api.nvim_create_user_command("LspInfo", function()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	if #clients == 0 then
		vim.notify("No LSP clients attached to this buffer", vim.log.levels.WARN)
		return
	end
	local lines = { "LSP clients attached to this buffer:", "" }
	for _, client in ipairs(clients) do
		table.insert(lines, ("  %s (id: %d)"):format(client.name, client.id))
		table.insert(lines, ("    root: %s"):format(client.root_dir or "none"))
		table.insert(lines, ("    filetypes: %s"):format(table.concat(client.config.filetypes or {}, ", ")))
		table.insert(lines, "")
	end
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "Show LSP info for current buffer" })

vim.api.nvim_create_user_command("LspLog", function()
	vim.cmd.edit(vim.lsp.get_log_path())
end, { desc = "Open LSP log file" })

vim.api.nvim_create_user_command("LspRestart", function()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	for _, client in ipairs(clients) do
		local name = client.name
		vim.lsp.stop_client(client.id)
		vim.defer_fn(function()
			vim.lsp.enable(name)
			vim.notify("Restarted " .. name, vim.log.levels.INFO)
		end, 500)
	end
end, { desc = "Restart LSP clients for current buffer" })

vim.api.nvim_create_user_command("Run", function(opts)
	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(buf, "Run Output")
	vim.cmd("botright split")
	vim.api.nvim_win_set_buf(0, buf)
	vim.fn.jobstart(opts.args, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = function(_, data)
			if data then
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
			end
		end,
		on_stderr = function(_, data)
			if data then
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, data)
			end
		end,
	})
end, { nargs = "+", complete = "shellcmd" })

vim.api.nvim_create_user_command("TypstPin", function()
	local client = vim.lsp.get_clients({ name = "tinymist" })[1]
	if not client then
		return vim.notify("tinymist not running!", vim.log.levels.ERROR)
	end
	client.request("workspace/executeCommand", {
		command = "tinymist.pinMain",
		arguments = { vim.api.nvim_buf_get_name(0) },
	}, function(err)
		vim.notify(
			err and ("error pinning: " .. err) or "successfully pinned",
			err and vim.log.levels.ERROR or vim.log.levels.INFO
		)
	end)
end, {})
