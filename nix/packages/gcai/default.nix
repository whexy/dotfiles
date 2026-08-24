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
pkgs.writeShellScriptBin "gcai" ''
  set -euo pipefail

  PATH="${pkgs.git}/bin:${pi}/bin:${pkgs.coreutils}/bin:${pkgs.gnused}/bin"

  model="''${GCAI_MODEL:-opencode-go/deepseek-v4-flash}"

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "gcai: not a git repository" >&2
    exit 1
  fi

  if git diff --staged --quiet; then
    echo "gcai: no staged changes (stage files with git add first)" >&2
    exit 1
  fi

  # Cap the diff so a huge refactor doesn't blow the model's context.
  diff=$(git diff --staged --no-color | head -c 20000)
  subjects=$(git log -8 --format=%s 2>/dev/null || true)

  message=$(
    pi -p --no-session \
      --model "$model" \
      "Write a commit message for these staged changes.
      Reply with only the commit message text: plain text, no code fences, no surrounding quotes.

      Recent commit subjects for style reference:
      $subjects

      Staged diff:
      $diff"
  )

  # Strip stray code fences and leading blank lines from the reply.
  message=$(printf '%s\n' "$message" | sed -e '/^```/d' -e '/./,$!d')

  if [ -z "$message" ]; then
    echo "gcai: pi returned an empty message" >&2
    exit 1
  fi

  git commit -e -m "$message" "$@"
''
