# List available commands
default:
    @just --list

# Update every flake input, then every package that pins an upstream release
update: update-inputs update-packages

# Update flake inputs (all or the named ones)
update-inputs *INPUT:
    nix flake update {{INPUT}}

# Update packages' upstream pins (all or the named ones)
update-packages *PACKAGE:
    nix run .#update -- {{PACKAGE}}

# Run format + lint pre-commit checks (treefmt + statix + nil + deadnix)
check:
    #!/usr/bin/env bash
    set -euo pipefail
    SYSTEM=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    echo "=== Running pre-commit checks ($SYSTEM) ==="
    nix build ".#checks.${SYSTEM}.pre-commit" -L --no-link
    echo "SUCCESS - All lint checks passed"

# Check that the pinned nightly Neovim is present in nix-community.cachix.org.
# A miss means upstream moved flake/dev/flake.lock, which is the signal to bump
# the neovim-nightly-nixpkgs pin in flake.nix.
check-nvim-cache:
    #!/usr/bin/env bash
    set -euo pipefail
    status=0
    for system in x86_64-linux aarch64-linux aarch64-darwin; do
        path=$(nix eval --raw --impure --expr \
            "(builtins.getFlake (toString ./.)).inputs.neovim-nightly.packages.${system}.default.outPath")
        hash=${path#/nix/store/}
        hash=${hash%%-*}
        code=$(curl -sS -o /dev/null -w '%{http_code}' "https://nix-community.cachix.org/${hash}.narinfo")
        if [ "$code" = 200 ]; then
            echo "OK   - $system: ${path##*/}"
        else
            echo "MISS - $system: ${path##*/} (narinfo HTTP $code)"
            status=1
        fi
    done
    if [ "$status" -ne 0 ]; then
        echo "Nightly Neovim would build from source; bump neovim-nightly-nixpkgs in flake.nix."
        exit 1
    fi
    echo "SUCCESS - nightly Neovim is cached for all systems"

# Verify primary configurations evaluate correctly (ellison)
verify:
    @echo "=== Verifying primary configurations ==="
    @echo "Evaluating ellison..."
    nix eval .#nixosConfigurations.ellison.config.system.build.toplevel.drvPath --show-trace
    @echo "OK - ellison"
    @echo "Checking package updaters..."
    nix build ".#checks.$(nix eval --raw --impure --expr builtins.currentSystem).package-updaters" --no-link
    @echo "OK - package updaters"
    @echo "SUCCESS - All primary configurations evaluate correctly"
