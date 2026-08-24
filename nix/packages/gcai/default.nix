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
    model="''${GCAI_MODEL:-opencode-go/deepseek-v4-flash}"

    message=$(
      pi -p --no-session \
        --model "$model" \
        "Write a commit message for the staged changes in this repository.
        Follow VCS rules. Reply with plain text, no code fences, no surrounding quotes.
        You are pi, a coding agent. Provider and model: $model."
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
