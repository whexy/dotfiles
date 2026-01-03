all: output.css pretty

output.css: index.html input.css
	nix run nixpkgs#tailwindcss_4 -- -i input.css -o output.css --minify

pretty: index.html
	nix shell nixpkgs#nodePackages.prettier -c prettier index.html --write

.phony: all pretty
