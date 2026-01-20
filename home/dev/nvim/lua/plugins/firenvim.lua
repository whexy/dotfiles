return {
	{
		"glacambre/firenvim",
		lazy = false,
		build = ":call firenvim#install(0)",
		init = function()
			vim.g.firenvim_config = {
				localSettings = {
					[".*"] = {
						takeover = "never",

						-- Broaden what Firenvim can attach to
						-- textarea: classic textareas
						-- div[role="textbox"]: many rich editors (Gmail etc.)
						-- [contenteditable="true"]: Google Docs-like / web editors
						selector = [[textarea:not([readonly],[aria-readonly]),
                        div[role="textbox"],
                        [contenteditable="true"]],
					},
				},
			}
		end,
	},
}
