import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { Manifest, setLogger } from "release-please";
import { buildStrategy } from "release-please/build/src/factory.js";
import { Version } from "release-please/build/src/version.js";
import { TagName } from "release-please/build/src/util/tag-name.js";
import { githubToken } from "./github-app.mjs";
import { imageDigest, publishRelease } from "./publish-release.mjs";

const env = {
  CI_PIPELINE_EVENT: "tag",
  CI_REPO: "whexy/example",
  CI_COMMIT_TAG: "v0.1.0-alpha.3",
  CI_COMMIT_SHA: "abc123",
  GHCR_TOKEN: "registry-secret",
};
const digest = `sha256:${"a".repeat(64)}`;
const quiet = () => {};
setLogger({
  error: quiet,
  warn: quiet,
  info: quiet,
  debug: quiet,
  trace: quiet,
});

function fixture({ draft = true, missing = false, digestError } = {}) {
  const calls = [];
  let waits = 0;
  return {
    calls,
    get waits() {
      return waits;
    },
    deps: {
      tokenFor: async () => "app-token",
      digestFor: async (repository) => {
        assert.equal(repository, env.CI_REPO);
        if (digestError) throw new Error(digestError);
        return digest;
      },
      wait: async () => {
        waits++;
      },
      request: async (_token, path, options) => {
        calls.push({ path, options });
        if (path.includes("?per_page="))
          return missing ? [] : [{ id: 7, tag_name: env.CI_COMMIT_TAG, draft }];
        if (path.endsWith("generate-notes"))
          return { body: "## What's Changed\n* Feature by @whexy in #4" };
        if (options?.method === "PATCH")
          return {
            html_url: `https://github.com/${env.CI_REPO}/releases/tag/${env.CI_COMMIT_TAG}`,
          };
        throw new Error(`Unexpected request: ${path}`);
      },
    },
  };
}

test("App authentication signs a valid JWT and restricts the installation token to this repository", async () => {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", {
    modulusLength: 2048,
  });
  const token = await githubToken(
    {
      GITHUB_APP_ID: "123",
      GITHUB_APP_INSTALLATION_ID: "456",
      GITHUB_APP_PRIVATE_KEY: privateKey,
      CI_REPO_NAME: "example",
    },
    async (url, options) => {
      assert.equal(
        url,
        "https://api.github.com/app/installations/456/access_tokens",
      );
      assert.deepEqual(JSON.parse(options.body), { repositories: ["example"] });
      const [header, payload, signature] = options.headers.authorization
        .slice(7)
        .split(".");
      assert.equal(JSON.parse(Buffer.from(payload, "base64url")).iss, "123");
      assert.ok(
        verify(
          "RSA-SHA256",
          Buffer.from(`${header}.${payload}`),
          publicKey,
          Buffer.from(signature, "base64url"),
        ),
      );
      return Response.json({ token: "installation-token" });
    },
  );
  assert.equal(token, "installation-token");
});

test("release PR advances the version in every shipped file", async () => {
  const contents = async (path) => {
    const parsedContent = await readFile(
      new URL(`../${path}`, import.meta.url),
      "utf8",
    );
    return {
      parsedContent,
      content: Buffer.from(parsedContent).toString("base64"),
      sha: "test",
    };
  };
  const github = {
    repository: { owner: "whexy", repo: "example", defaultBranch: "main" },
    getFileJson: async (path) =>
      JSON.parse((await contents(path)).parsedContent),
    getFileContentsOnBranch: contents,
    getFileContents: contents,
    findFilesByFilenameAndRef: async () => [],
    findFilesByGlobAndRef: async () => [],
    generateReleaseNotes: async () =>
      "## What's Changed\n* Example feature by @whexy in #4",
  };
  const manifest = await Manifest.fromManifest(github, "main");
  const config = manifest.repositoryConfig["."];
  // The tag pipeline builds from the forced tag while the release stays a draft.
  assert.equal(config.draft, true);
  assert.equal(config.forceTag, true);
  assert.equal(config.includeComponentInTag, false);
  // Before the first release the manifest is empty and initial-version applies.
  const current = JSON.parse(
    (await contents(".release-please-manifest.json")).parsedContent,
  )["."];
  const strategy = await buildStrategy({
    ...config,
    github,
    targetBranch: "main",
  });
  const release = await strategy.buildReleasePullRequest(
    [
      {
        sha: "new-sha",
        message: "feat: add a feature",
        type: "feat",
        scope: null,
        bareMessage: "add a feature",
        breaking: false,
        notes: [],
        references: [],
        files: [],
      },
    ],
    current && {
      tag: new TagName(Version.parse(current)),
      sha: "old-sha",
      notes: "",
    },
  );
  const next = release.version.toString();
  if (current) assert.notEqual(next, current);
  else assert.equal(next, config.initialVersion);
  for (const extra of config.extraFiles ?? []) {
    const path = typeof extra === "string" ? extra : extra.path;
    const update = release.updates.find((candidate) => candidate.path === path);
    assert.ok(update, `Missing release update for ${path}`);
    const updated = update.updater.updateContent(
      (await contents(path)).parsedContent,
    );
    assert.ok(updated.includes(next), `Version not updated in ${path}`);
    if (current)
      assert.ok(
        !updated.split(next).join("").includes(current),
        `Stale version left in ${path}`,
      );
  }
});

test("published notes contain PR credits and an immutable container reference", async () => {
  const f = fixture();
  await publishRelease(env, "0.1.0-alpha.3", f.deps);
  const publication = f.calls.find((call) => call.options?.method === "PATCH")
    .options.body;
  assert.equal(publication.draft, false);
  assert.equal(publication.prerelease, true);
  assert.equal(publication.make_latest, "false");
  assert.ok(publication.body.includes(`ghcr.io/${env.CI_REPO}@${digest}`));
  assert.ok(publication.body.includes("by @whexy in #4"));
});

test("stable release becomes Latest", async () => {
  const f = fixture();
  f.deps.request = async (_token, path, options) => {
    f.calls.push({ path, options });
    if (path.includes("?")) return [{ id: 7, tag_name: "v0.1.0", draft: true }];
    return { body: "notes", html_url: "release-url" };
  };
  await publishRelease({ ...env, CI_COMMIT_TAG: "v0.1.0" }, "0.1.0", f.deps);
  const body = f.calls.find((call) => call.options?.method === "PATCH").options
    .body;
  assert.equal(body.prerelease, false);
  assert.equal(body.make_latest, "true");
});

test("failed image lookup leaves the release as a draft", async () => {
  const f = fixture({ digestError: "image missing" });
  await assert.rejects(
    publishRelease(env, "0.1.0-alpha.3", f.deps),
    /image missing/,
  );
  assert.ok(!f.calls.some((call) => call.options?.method === "PATCH"));
});

test("missing draft waits for the tag/draft creation race, then fails without publishing", async () => {
  const f = fixture({ missing: true });
  await assert.rejects(
    publishRelease(env, "0.1.0-alpha.3", f.deps),
    /No release-please draft/,
  );
  assert.equal(f.waits, 5);
  assert.ok(!f.calls.some((call) => call.options?.method === "PATCH"));
});

test("rerunning finalization leaves an already published release unchanged", async () => {
  const f = fixture({ draft: false });
  await publishRelease(env, "0.1.0-alpha.3", f.deps);
  assert.equal(f.calls.length, 1);
});

test("PR events and mismatched tags cannot publish", async () => {
  const f = fixture();
  await assert.rejects(
    publishRelease(
      { ...env, CI_PIPELINE_EVENT: "pull_request" },
      "0.1.0-alpha.3",
      f.deps,
    ),
    /tag event/,
  );
  await assert.rejects(
    publishRelease(env, "0.1.0-alpha.4", f.deps),
    /match the release manifest/,
  );
  assert.equal(f.calls.length, 0);
});

test("registry digest comes from the published manifest and malformed responses fail", async () => {
  let calls = 0;
  const fetcher = async (url, options) => {
    calls++;
    if (url.includes("/token?")) {
      assert.ok(url.includes(`repository:${env.CI_REPO}:pull`));
      return Response.json({ token: "pull-token" });
    }
    assert.equal(
      url,
      `https://ghcr.io/v2/${env.CI_REPO}/manifests/0.1.0-alpha.3`,
    );
    assert.equal(options.method, "HEAD");
    assert.equal(options.headers.authorization, "Bearer pull-token");
    return new Response(null, { headers: { "docker-content-digest": digest } });
  };
  assert.equal(
    await imageDigest(env.CI_REPO, "0.1.0-alpha.3", "secret", fetcher),
    digest,
  );
  assert.equal(calls, 2);
  await assert.rejects(
    imageDigest(env.CI_REPO, "0.1.0-alpha.3", "secret", async (url) =>
      url.includes("/token?")
        ? Response.json({ token: "pull-token" })
        : new Response(null),
    ),
    /invalid image digest/,
  );
});
