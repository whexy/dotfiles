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

# Evaluate every host and standalone home, as CI does (EVAL_JOBS=4 runs four at once)
verify:
    ci/eval-all.sh
    @echo "Checking package updaters..."
    nix build ".#checks.$(nix eval --raw --impure --expr builtins.currentSystem).package-updaters" --no-link
    @echo "OK - package updaters"
