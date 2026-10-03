import { readFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import { setTimeout as sleep } from "node:timers/promises";
import { githubRequest, githubToken } from "./github-app.mjs";

export function releaseVersion(env, manifestVersion) {
  if (env.CI_PIPELINE_EVENT !== "tag")
    throw new Error("Release publication requires a tag event");
  if (env.CI_COMMIT_TAG !== `v${manifestVersion}`)
    throw new Error("Release tag must match the release manifest");
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(manifestVersion))
    throw new Error("Invalid release version");
  return manifestVersion;
}

export async function imageDigest(repository, version, token, fetcher = fetch) {
  if (!token) throw new Error("Missing GHCR_TOKEN");
  const [owner] = repository.split("/");
  const auth = await fetcher(
    `https://ghcr.io/token?service=ghcr.io&scope=repository:${repository}:pull`,
    {
      headers: {
        authorization: `Basic ${Buffer.from(`${owner}:${token}`).toString("base64")}`,
      },
      signal: AbortSignal.timeout(30_000),
    },
  );
  if (!auth.ok) throw new Error(`GHCR authentication: HTTP ${auth.status}`);
  const credentials = await auth.json();
  if (!credentials.token)
    throw new Error("GHCR response did not include a token");
  const response = await fetcher(
    `https://ghcr.io/v2/${repository}/manifests/${version}`,
    {
      method: "HEAD",
      headers: {
        authorization: `Bearer ${credentials.token}`,
        accept:
          "application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json",
      },
      signal: AbortSignal.timeout(30_000),
    },
  );
  if (!response.ok) throw new Error(`GHCR manifest: HTTP ${response.status}`);
  const digest = response.headers.get("docker-content-digest");
  if (!/^sha256:[a-f0-9]{64}$/.test(digest ?? ""))
    throw new Error("GHCR returned an invalid image digest");
  return digest;
}

export async function publishRelease(
  env,
  manifestVersion,
  {
    request = githubRequest,
    tokenFor = githubToken,
    digestFor = imageDigest,
    wait = sleep,
  } = {},
) {
  const version = releaseVersion(env, manifestVersion);
  const repository = env.CI_REPO;
  const token = await tokenFor(env);
  const root = `/repos/${repository}`;
  let release;
  // Forced tag creation triggers CI before release-please creates its draft.
  for (let attempt = 0; attempt < 6 && !release; attempt++) {
    for (let page = 1; ; page++) {
      const releases = await request(
        token,
        `${root}/releases?per_page=100&page=${page}`,
      );
      release = releases.find(
        (candidate) => candidate.tag_name === env.CI_COMMIT_TAG,
      );
      if (release || releases.length < 100) break;
    }
    if (!release && attempt < 5) await wait(1000 * 2 ** attempt);
  }
  if (!release)
    throw new Error(
      `No release-please draft found for ${env.CI_COMMIT_TAG}; rerun the tag pipeline after preparation succeeds`,
    );
  if (!release.draft) {
    console.log(`${env.CI_COMMIT_TAG} is already published`);
    return;
  }
  const digest = await digestFor(repository, version, env.GHCR_TOKEN);
  const notes = await request(token, `${root}/releases/generate-notes`, {
    method: "POST",
    body: { tag_name: env.CI_COMMIT_TAG, target_commitish: env.CI_COMMIT_SHA },
  });
  const body = `## Container\n\n\`ghcr.io/${repository}:${version}\` (linux/amd64)\n\nImmutable reference:\n\n\`ghcr.io/${repository}@${digest}\`\n\n${notes.body}`;
  const result = await request(token, `${root}/releases/${release.id}`, {
    method: "PATCH",
    body: {
      name: env.CI_COMMIT_TAG,
      body,
      draft: false,
      prerelease: version.includes("-"),
      make_latest: version.includes("-") ? "false" : "true",
    },
  });
  console.log(`Published ${result.html_url}`);
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  const manifest = JSON.parse(
    await readFile(
      new URL("../.release-please-manifest.json", import.meta.url),
      "utf8",
    ),
  );
  await publishRelease(process.env, manifest["."]);
}
