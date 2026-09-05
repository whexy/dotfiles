{
  pkgs,
  inputs,
  system,
}:

let
  pi = inputs.llm-agents.packages.${system}.pi;
in
# Generate a commit message with pi and open it in $EDITOR for review
# before committing (git commit -e).
#
# Usage:
#   gcai [extra git commit args...]
#
pkgs.writeShellApplication {
  name = "gcai";

  runtimeInputs = [
    pkgs.git
    pkgs.gnused
    pi
  ];

  text = ''
    # The Home Manager wrapper picks the model from the host's account
    # tier; there is no sensible provider-agnostic default here.
    if [ -z "''${GCAI_MODEL:-}" ]; then
      echo "gcai: GCAI_MODEL is not set" >&2
      exit 1
    fi

    message=$(
      pi -p --no-session \
        --model "$GCAI_MODEL" \
        "Write a commit message for the staged changes in this repository.
        Follow VCS rules. Reply with plain text, no code fences, no surrounding quotes."
    )

    # Strip stray code fences and leading blank lines from the reply.
    message=$(printf '%s\n' "$message" | sed -e '/^```/d' -e '/./,$!d')

    if [ -z "$message" ]; then
      echo "gcai: pi returned an empty message" >&2
      exit 1
    fi

    git commit -e -m "$message" "$@"
  '';
}
