local language_packages = require("language_packages")

local function build_formatter_map(formatter_list)
	local map = {}

	for _, item in ipairs(formatter_list) do
		local lang = item.language
		local name = item.name

		if lang and name then
			map[lang] = map[lang] or {}
			table.insert(map[lang], name)
		end
	end

	return map
end

return {
	{
		"stevearc/conform.nvim",
		event = "BufWritePre", -- auto load before saving any files
		keys = {
			{
				"<leader>cf",
				function()
					require("conform").format({
						async = true,
						lsp_fallback = true,
						timeout_ms = 500,
					})
				end,
				{ desc = "Format file" },
			},
		},
		opts = {
			format_on_save = {
				lsp_fallback = true,
				timeout_ms = 500,
			},
			formatters_by_ft = build_formatter_map(language_packages.FORMATTERS),
		},
	},
}
