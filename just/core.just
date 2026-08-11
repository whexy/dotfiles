# List available commands
default:
    @just --list

# Update flake inputs (all or specific input)
update *INPUT:
    @if [ -z "{{INPUT}}" ]; then \
        echo "Updating all flake inputs..."; \
        nix flake update; \
    else \
        echo "Updating {{INPUT}}..."; \
        nix flake update {{INPUT}}; \
    fi

# Run format + lint pre-commit checks (treefmt + statix + nil + deadnix)
check:
    #!/usr/bin/env bash
    set -euo pipefail
    SYSTEM=$(nix eval --raw --impure --expr 'builtins.currentSystem')
    echo "=== Running pre-commit checks ($SYSTEM) ==="
    nix build ".#checks.${SYSTEM}.pre-commit" -L --no-link
    echo "SUCCESS - All lint checks passed"

# Verify primary configurations evaluate correctly (ellison, mudd)
verify:
    @echo "=== Verifying primary configurations ==="
    @echo "Evaluating ellison..."
    nix eval .#nixosConfigurations.ellison.config.system.build.toplevel.drvPath --show-trace
    @echo "OK - ellison"
    @echo "Evaluating mudd..."
    nix eval .#nixosConfigurations.mudd.config.system.build.toplevel.drvPath --show-trace
    @echo "OK - mudd"
    @echo "SUCCESS - All primary configurations evaluate correctly"
