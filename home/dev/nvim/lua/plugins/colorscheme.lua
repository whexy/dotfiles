return {
	{
		-- dracula theme, customized version copied from "dracula pro"
		"Mofiqul/dracula.nvim",
		enabled = false,
		lazy = false,
		priority = 1000,
		opts = {
			colors = {
				bg = "#29202B", -- hsl(289,14%,15%)
				fg = "#F7F7F1", -- hsl(60,30%,96%)
				red = "#FF947F", -- hsl(10,100%,75%)
				orange = "#FFC97F", -- hsl(35,100%,75%)
				yellow = "#FEFF7F", -- hsl(60,100%,75%)
				green = "#8AFF7F", -- hsl(115,100%,75%)
				cyan = "#7FFFE9", -- hsl(170,100%,75%)
				blue = "#7FBFFF", -- hsl(210,100%,75%)
				pink = "#FF7FBF", -- hsl(330,100%,75%)
				purple = "#947FFF", -- hsl(250,100%,75%)
				shadow = "#000000", -- hsl(0,0%,0%)
				darken = "#212121", -- hsl(0,0%,13%)

				selection = "#534157", -- color(bg) s(15%) l(30%)
				comment = "#9E6FA8", -- color(bg) s(25%) l(55%)
				visual = "#492F4F", -- color(bg) s(25%) l(25%)
				stack = "#E77FFF", -- color(comment) s(100%) l(75%)

				bright_red = "#FFBFB2", -- red   l+10%
				bright_orange = "#FFDFB2", -- orange l+10%
				bright_yellow = "#FFFFB2", -- yellow l+10%
				bright_green = "#B8FFB2", -- green  l+10%
				bright_cyan = "#B2FFF2", -- cyan   l+10%
				bright_blue = "#B2D8FF", -- blue   l+10%
				bright_pink = "#FFB2D8", -- pink   l+10%
				bright_purple = "#BFB2FF", -- purple l+10%
				bright_white = "#FFFFFF", -- pure white

				white = "#F7F7F1", -- same as fg
				black = "#000000", -- same as shadow
				menu = "#241C25", -- bg.l - 2
				gutter_fg = "#84568F", -- comment.l - 10
				nontext = "#584D5A", -- invisibles: color(comment) s×0.3, l×0.6
			},
			transparent_bg = false,
			overrides = {
				NormalFloat = { bg = "#241C25" },
				FloatBorder = { fg = "#BFB2FF", bg = "#241C25" },

				NoiceCmdlinePopupBorder = { fg = "#BFB2FF" },
			},
		},
		config = function(_, opts)
			require("dracula").setup(opts)
			vim.cmd.colorscheme("dracula")
		end,
	},

	{
		"ellisonleao/gruvbox.nvim",
		lazy = false,
		priority = 1000,
		opts = function()
			vim.cmd.colorscheme("gruvbox")
		end,
	},
}
