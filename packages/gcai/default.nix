{
  pkgs,
  inputs,
  system,
}:

let
  # Blueprint's flake-level pkgs carries no overlays, so match the llm-tools
  # overlay's Node build of pi here instead of inheriting it.
  pi = inputs.llm-agents.packages.${system}.pi.override { useBun = false; };
in
# Generate a commit message with pi and open it in $EDITOR for review
# before committing (git commit -e).
#
# Usage:
#   gcai [extra git commit args...]
# Retry with the saved message:
#   git commit -e -F "$(git rev-parse --git-path GCAI_COMMIT_MSG)"
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

    message_file=$(git rev-parse --git-path GCAI_COMMIT_MSG)

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

    printf '%s\n' "$message" > "$message_file"

    if git commit -e -F "$message_file" "$@"; then
      exit 0
    else
      status=$?
      echo "gcai: commit failed; generated message saved at $message_file" >&2
      echo "Retry: git commit -e -F \"\$(git rev-parse --git-path GCAI_COMMIT_MSG)\" [extra git commit args...]" >&2
      exit "$status"
    fi
  '';
}
