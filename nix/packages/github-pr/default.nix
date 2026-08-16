{ pkgs }:

# Turn the current (possibly dirty) worktree into a PR authored by a GitHub
# App. Designed for CI (see .woodpecker.yml update-flake): after `nix flake
# update` dirties flake.lock, this script creates a branch, commits the
# changes, pushes it, and opens a PR as the App's bot user.
#
# It mints an installation access token from the App credentials (the
# token-minting logic mirrors ../github-app-token) and derives the bot's git
# identity (login/id) from the GitHub API, so commits and the PR both show up
# as "<app-slug>[bot]".
#
# Required environment:
#   GITHUB_APP_ID              App ID
#   GITHUB_APP_PRIVATE_KEY     App private key (PEM contents)
#   GITHUB_APP_INSTALLATION_ID Installation ID for the target repo/org
#
# Usage:
#   github-pr [options] [-- paths...]
#     --branch NAME   branch to create/reset (default: github-pr/<timestamp>)
#     --base BRANCH   PR base (default: repo default branch)
#     --title TITLE   PR title (default: the commit message)
#     --body BODY     PR body (default: empty)
#     --message MSG   commit message (default: "chore: automated update")
#     --draft         open the PR as a draft
#     -- paths...     files to stage (default: all changes, `git add -A`)
#
# Re-running with the same --branch force-pushes and reuses the open PR, so a
# recurring cron job keeps a single up-to-date PR.
#
# Every external command is referenced by absolute store path so the script's
# nix closure is self-contained (see ../github-app-token).
pkgs.writeShellScriptBin "github-pr" ''
    set -euo pipefail

    usage() {
      ${pkgs.coreutils}/bin/cat >&2 <<'EOF'
  Usage: github-pr [options] [-- paths...]
    --branch NAME   branch to create/reset (default: github-pr/<timestamp>)
    --base BRANCH   PR base (default: repo default branch)
    --title TITLE   PR title (default: the commit message)
    --body BODY     PR body (default: empty)
    --message MSG   commit message (default: "chore: automated update")
    --draft         open the PR as a draft
    -- paths...     files to stage (default: all changes, `git add -A`)

  Requires GITHUB_APP_ID, GITHUB_APP_PRIVATE_KEY, GITHUB_APP_INSTALLATION_ID.
  EOF
    }

    branch=""
    base=""
    title=""
    body=""
    message="chore: automated update"
    draft=0

    while [ $# -gt 0 ]; do
      case "$1" in
        --branch) branch=$2; shift 2 ;;
        --base) base=$2; shift 2 ;;
        --title) title=$2; shift 2 ;;
        --body) body=$2; shift 2 ;;
        --message | -m) message=$2; shift 2 ;;
        --draft) draft=1; shift ;;
        --) shift; break ;;
        -h | --help) usage; exit 0 ;;
        *) echo "github-pr: unknown option: $1" >&2; usage >&2; exit 1 ;;
      esac
    done

    for var in GITHUB_APP_ID GITHUB_APP_PRIVATE_KEY GITHUB_APP_INSTALLATION_ID; do
      if [ -z "''${!var:-}" ]; then
        echo "github-pr: $var is not set" >&2
        exit 1
      fi
    done

    # `gh` shells out to git to inspect the repo/branch.
    export PATH="${pkgs.git}/bin:$PATH"

    b64url() {
      ${pkgs.openssl}/bin/openssl base64 -A |
        ${pkgs.coreutils}/bin/tr '+/' '-_' |
        ${pkgs.coreutils}/bin/tr -d '='
    }

    # --- Mint an installation access token -------------------------------------
    echo "==> Minting installation access token"
    now=$(${pkgs.coreutils}/bin/date +%s)
    header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)
    payload=$(
      printf '{"iat":%d,"exp":%d,"iss":"%s"}' \
        "$((now - 60))" "$((now + 600))" "$GITHUB_APP_ID" |
        b64url
    )
    unsigned="$header.$payload"
    signature=$(
      printf '%s' "$unsigned" |
        ${pkgs.openssl}/bin/openssl dgst \
          -sha256 \
          -sign <(printf '%s' "$GITHUB_APP_PRIVATE_KEY") \
          -binary |
        b64url
    )
    token_response=$(
      ${pkgs.curl}/bin/curl -sS -w '\n%{http_code}' -X POST \
        -H "Authorization: Bearer $unsigned.$signature" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/app/installations/$GITHUB_APP_INSTALLATION_ID/access_tokens"
    )
    token_status=$(printf '%s' "$token_response" | ${pkgs.coreutils}/bin/tail -n1)
    token_body=$(printf '%s' "$token_response" | ${pkgs.gnused}/bin/sed '$d')
    if [ "$token_status" -ge 400 ]; then
      echo "github-pr: token request failed (HTTP $token_status):" >&2
      echo "$token_body" >&2
      exit 1
    fi
    GH_TOKEN=$(
      printf '%s' "$token_body" |
        ${pkgs.gnused}/bin/sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
    )
    if [ -z "$GH_TOKEN" ]; then
      echo "github-pr: failed to parse installation token" >&2
      exit 1
    fi
    export GH_TOKEN

    # --- Commit as the App's bot user ------------------------------------------
    # GET /user rejects installation tokens (403 "Resource not accessible by
    # integration"), so resolve the bot identity via endpoints that accept
    # them: GET /app (JWT) for the app slug, then GET /users/<slug>[bot] for
    # the bot user's login and numeric ID.
    echo "==> Resolving bot identity"
    app=$(
      ${pkgs.curl}/bin/curl -fsS \
        -H "Authorization: Bearer $unsigned.$signature" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/app"
    )
    app_slug=$(printf '%s' "$app" | ${pkgs.gnused}/bin/sed -n 's/.*"slug"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    bot=$(
      ${pkgs.curl}/bin/curl -fsS \
        -H "Authorization: Bearer $GH_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/users/$app_slug%5Bbot%5D"
    )
    bot_login=$(printf '%s' "$bot" | ${pkgs.gnused}/bin/sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    bot_id=$(printf '%s' "$bot" | ${pkgs.gnused}/bin/sed -n 's/.*"id"[[:space:]]*:[[:space:]]*\([0-9]\+\).*/\1/p')
    git config user.name "$bot_login"
    git config user.email "$bot_id+$bot_login@users.noreply.github.com"

    # --- Branch, stage, commit ---------------------------------------------------
    if [ -z "$branch" ]; then
      branch="github-pr/$(${pkgs.coreutils}/bin/date +%Y%m%d%H%M%S)"
    fi

    # -B creates or resets the branch; dirty worktree changes carry over.
    git checkout -B "$branch"

    if [ $# -gt 0 ]; then
      git add -- "$@"
    else
      git add -A
    fi

    if git diff --cached --quiet; then
      echo "github-pr: no changes to commit"
      exit 0
    fi

    echo "==> Committing changes on branch '$branch'"
    git commit -m "$message"

    # --- Push with the installation token ---------------------------------------
    # Point origin at a token-authenticated URL just for the push, then restore
    # it so the token does not linger in .git/config.
    echo "==> Pushing to origin"
    origin_url=$(git remote get-url origin)
    repo=$(printf '%s' "$origin_url" |
      ${pkgs.gnused}/bin/sed -e 's#.*github\.com[:/]##' -e 's#\.git$##')
    restore_origin() {
      git remote set-url origin "$origin_url"
    }
    trap restore_origin EXIT
    git remote set-url origin "https://x-access-token:$GH_TOKEN@github.com/$repo.git"
    git push -u --force-with-lease origin "$branch"
    restore_origin
    trap - EXIT

    # --- Open (or reuse) the PR -------------------------------------------------
    echo "==> Opening PR"
    if ${pkgs.gh}/bin/gh pr view "$branch" --json url >/dev/null 2>&1; then
      echo "github-pr: PR for branch '$branch' already exists; updated via push:"
      ${pkgs.gh}/bin/gh pr view "$branch" --json url --jq .url
      exit 0
    fi

    set --
    set -- "$@" --title "''${title:-$message}"
    if [ -n "$body" ]; then set -- "$@" --body "$body"; fi
    if [ -n "$base" ]; then set -- "$@" --base "$base"; fi
    if [ "$draft" -eq 1 ]; then set -- "$@" --draft; fi

    exec ${pkgs.gh}/bin/gh pr create "$@"
''
