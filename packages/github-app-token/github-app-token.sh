b64url() {
  openssl base64 -A |
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
    openssl dgst \
      -sha256 \
      -sign <(printf '%s' "$GITHUB_APP_PRIVATE_KEY") \
      -binary |
    b64url
)
jwt="$unsigned.$signature"

# --app-slug prints the App's slug, which names its bot user ("<slug>[bot]").
# Must use JWT auth: GET /app rejects installation tokens.
if [ "${1:-}" = "--app-slug" ]; then
  curl -fsS --retry 3 \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/app" |
    jq -er .slug
  exit 0
fi

# jq -e fails on a missing/null token field, so a malformed success body
# cannot silently produce an empty token that 401s downstream.
curl -fsS --retry 3 -X POST \
  -H "Authorization: Bearer $jwt" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/app/installations/$GITHUB_APP_INSTALLATION_ID/access_tokens" |
  jq -er .token
