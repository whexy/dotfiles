{ pkgs }:

pkgs.writeShellScriptBin "github-app-token" ''
  set -euo pipefail

  b64url() {
    ${pkgs.openssl}/bin/openssl base64 -A |
      tr '+/' '-_' |
      tr -d '='
  }

  now=$(date +%s)
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

  curl -fsS -X POST \
    -H "Authorization: Bearer $unsigned.$signature" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app/installations/$GITHUB_APP_INSTALLATION_ID/access_tokens" |
    sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
''
