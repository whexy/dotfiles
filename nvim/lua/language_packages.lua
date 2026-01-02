local M = {}

-- Tree-sitter packages
-- Automatically installed by nvim-treesitter
-- Require `tree-sitter` cli and `gcc`
M.TS_PACKAGES = {
	-- Shell
	"regex",
	"bash",
	-- LUA
	"lua",
	-- Serialized
	"yaml",
	"json5",
	-- Clangd
	"cpp",
	-- Python
	"python",
	"ninja",
	"rst",
	-- Rust
	"rust",
	"ron",
	-- Golang
	"go",
	"gomod",
	"gowork",
	"gosum",
	-- Typst
	"typst",
	-- Typescript / Javascript
	"typescript",
	"javascript",
	-- Nix
	"nix",
}

M.LSPS = {
	{ name = "jsonls" },
	{ name = "lua_ls" },
	{ name = "tombi" },
	{ name = "clangd" },
	{ name = "basedpyright" },
	{ name = "ruff" },
	{ name = "gopls" },
	{ name = "tinymist" },
	{ name = "yaml-language-server" },
	{ name = "ts_ls" },
	{ name = "nil_ls" },
}

M.FORMATTERS = {
	{ language = "lua", name = "stylua" },
	{ language = "sh", name = "shfmt" },
	{ language = "yaml", name = "yamlfmt" },
	{ language = "python", name = "black" },
	{ language = "rust", name = "rustfmt" },
	{ language = "toml", name = "tombi" },
	{ language = "typst", name = "typstyle" },
	{ language = "nix", name = "nixfmt" },
}

M.LINTERS = {
	{ language = "sh", name = "shellcheck" },
	{ language = "toml", name = "tombi" },
	{ language = "go", name = "golangcilint" },
}

return M
