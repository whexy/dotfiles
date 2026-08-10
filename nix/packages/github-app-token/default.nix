{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "github-app-token";

  runtimeInputs = with pkgs; [
    openssl
    curl
    jq
    coreutils
  ];

  text = ''
    : "''${GITHUB_APP_ID:?GITHUB_APP_ID is required}"
    : "''${GITHUB_APP_INSTALLATION_ID:?GITHUB_APP_INSTALLATION_ID is required}"
    : "''${GITHUB_APP_PRIVATE_KEY:?GITHUB_APP_PRIVATE_KEY is required}"

    base64url() {
      openssl base64 -A |
        tr '+/' '-_' |
        tr -d '='
    }

    now="$(date +%s)"

    # GitHub recommends setting iat slightly in the past to tolerate
    # clock drift. JWT lifetime must not exceed 10 minutes.
    iat="$((now - 60))"
    exp="$((now + 600))"

    header="$(
      printf '%s' '{"alg":"RS256","typ":"JWT"}' |
        base64url
    )"

    payload="$(
      printf '{"iat":%d,"exp":%d,"iss":"%s"}' \
        "$iat" "$exp" "$GITHUB_APP_ID" |
        base64url
    )"

    unsigned="$header.$payload"

    signature="$(
      printf '%s' "$unsigned" |
        openssl dgst \
          -sha256 \
          -sign <(printf '%s' "$GITHUB_APP_PRIVATE_KEY") \
          -binary |
        base64url
    )"

    jwt="$unsigned.$signature"

    curl \
      --fail-with-body \
      --silent \
      --show-error \
      --request POST \
      --header "Authorization: Bearer $jwt" \
      --header "Accept: application/vnd.github+json" \
      --header "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/app/installations/$GITHUB_APP_INSTALLATION_ID/access_tokens" |
      jq --exit-status --raw-output '.token'
  '';
}
