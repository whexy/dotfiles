import { sign } from "node:crypto";

export async function githubRequest(
  token,
  path,
  { method = "GET", body } = {},
  fetcher = fetch,
) {
  const response = await fetcher(`https://api.github.com${path}`, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      accept: "application/vnd.github+json",
      "content-type": "application/json",
      "x-github-api-version": "2022-11-28",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(30_000),
  });
  if (!response.ok)
    throw new Error(`GitHub ${method} ${path}: HTTP ${response.status}`);
  return response.json();
}

export async function githubToken(env = process.env, fetcher = fetch) {
  // Local dry runs can use gh's token without storing it in the repository.
  if (env.GITHUB_TOKEN) return env.GITHUB_TOKEN;
  for (const name of [
    "GITHUB_APP_ID",
    "GITHUB_APP_INSTALLATION_ID",
    "GITHUB_APP_PRIVATE_KEY",
    "CI_REPO_NAME",
  ]) {
    if (!env[name]) throw new Error(`Missing ${name}`);
  }
  const now = Math.floor(Date.now() / 1000);
  const encode = (value) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${encode({
    iat: now - 60,
    exp: now + 600,
    iss: env.GITHUB_APP_ID,
  })}`;
  const jwt = `${unsigned}.${sign("RSA-SHA256", Buffer.from(unsigned), env.GITHUB_APP_PRIVATE_KEY).toString("base64url")}`;
  // The App is installed account-wide; scope each token to the repository being released.
  const result = await githubRequest(
    jwt,
    `/app/installations/${env.GITHUB_APP_INSTALLATION_ID}/access_tokens`,
    {
      method: "POST",
      body: { repositories: [env.CI_REPO_NAME] },
    },
    fetcher,
  );
  if (!result.token)
    throw new Error("GitHub App response did not include a token");
  return result.token;
}
