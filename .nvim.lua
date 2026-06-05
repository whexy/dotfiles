vim.lsp.config("nixd", {
	settings = {
		nixd = {
			nixpkgs = {
				expr = "import (builtins.getFlake (builtins.toString ./.)).inputs.nixpkgs { }",
			},
			formatting = {
				command = { "nixfmt" },
			},
			options = {
				nixos = {
					expr = "(builtins.getFlake (builtins.toString ./.)).nixosConfigurations.remote-dev.options",
				},
				["home-manager"] = {
					expr = "(builtins.getFlake (builtins.toString ./.)).nixosConfigurations.remote-dev.options.home-manager.users.type.getSubOptions []",
				},
			},
			diagnostic = {
				suppress = { "sema-extra-with" },
			},
		},
	},
})
