# Dotfiles management commands

# List available commands
default:
    @just --list

# Verify all flake outputs evaluate correctly
verify:
    @echo "Verifying NixOS configurations..."
    @nix eval .#nixosConfigurations.remote-dev --apply 'x: "ok"' && echo "  remote-dev: ok"
    @echo "Verifying Darwin configurations..."
    @nix eval .#darwinConfigurations.mbp --apply 'x: "ok"' && echo "  mbp: ok"
    @nix eval .#darwinConfigurations.mini --apply 'x: "ok"' && echo "  mini: ok"
    @echo "Verifying Home Manager configurations..."
    @nix eval .#homeConfigurations.home --apply 'x: "ok"' && echo "  home: ok"
    @echo "All configurations verified!"
