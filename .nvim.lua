local flake = "(builtins.getFlake (builtins.toString ./.))"

vim.lsp.config("nixd", {
	cmd = { "nixd" },
	filetypes = { "nix" },
	root_markers = { "flake.nix", ".git" },
	settings = {
		nixd = {
			nixpkgs = {
				expr = "import " .. flake .. ".inputs.nixpkgs { system = builtins.currentSystem; }",
			},
			formatting = {
				command = { "nixfmt" },
			},
			options = {
				-- All NixOS hosts import the shared dotfiles option declarations.
				nixos = {
					expr = flake .. ".nixosConfigurations.ellison.options",
				},
				darwin = {
					expr = flake .. ".darwinConfigurations.golf.options",
				},
				-- Blueprint exposes standalone homes below legacyPackages. This
				-- configuration imports homeModules.all, including dotfiles.*.
				["home-manager"] = {
					expr = flake .. '.legacyPackages.x86_64-linux.homeConfigurations."wenxuan@venus".options',
				},
			},
			diagnostic = {
				suppress = { "sema-extra-with" },
			},
		},
	},
})

vim.lsp.enable("nixd")
