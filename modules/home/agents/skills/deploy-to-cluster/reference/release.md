# release-please

release-please runs inside Woodpecker as `whexy-bot`. The tooling is
language-agnostic and lives in `release/` with its own pinned dependencies.
Generate its lockfile once with `npm install --prefix release` and commit
`release/package-lock.json`. Keep `release/` out of the project's own
packaging, linters and typecheck.

- `github-app.mjs` mints an App installation token scoped to `CI_REPO_NAME`.
- `release-please.mjs` opens or updates the release PR and creates releases.
- `publish-release.mjs` finalizes the draft release.
- `release.test.mjs` covers all three plus the configuration, and runs on
  every PR.

The flow:

1. Each push to the default branch opens or updates one release PR. Its PR
   pipeline validates the exact tree that will be published.
2. Merging the release PR makes the next push create the `v<version>` tag and
   a draft GitHub release.
3. The tag pipeline publishes the image. `publish-release` then writes notes
   with the image's digest and publishes the release.
4. A failed tag pipeline leaves the release as a draft. Fix the cause and
   rerun the tag pipeline.

Never create tags or releases by hand.

Settings in `release-please-config.json`:

- **Tags:** `include-component-in-tag: false`, so git tags are `v<version>`
  and image tags are the same version without the `v`.
- **Versioning:** `versioning: prerelease`, `prerelease-type: alpha`,
  `prerelease: true`, `bump-minor-pre-major` and
  `bump-patch-for-minor-pre-major`. New projects stay on the
  `0.1.0-alpha.<n>` line until Wenxuan decides to go stable.
- **Draft release and forced tag:** `draft: true` with `force-tag-creation:
true`. The tag exists at once and triggers the build, while the release
  stays a draft until its image exists. The tag event can arrive before the
  draft does, which is why `publish-release` retries.
- **Changelog:** `changelog-type: github`, so notes credit PRs and authors.
- **Release type:** set `release-type` to the language's type (`node`,
  `python`, `rust`, `go`), or `simple`.
- **Version files:** `extra-files` lists every other file that ships the
  version, starting with `Dockerfile`. Mark each version with a trailing
  `x-release-please-version` comment, or a `x-release-please-start-version` …
  `x-release-please-end` block. The release test fails if any listed file is
  not updated.
- **Starting point:**
  - `bootstrap-sha` is the full 40-character SHA of the default-branch HEAD
    before release-please was added. A short SHA is silently ignored.
  - `.release-please-manifest.json` starts as `{}`, and `initial-version`
    names the first release. Never seed the manifest with a placeholder
    version: GitHub changelog generation fails on a previous tag that does
    not exist.

The manifest is CI's version source. After the first release, release-please
owns it, so never edit it by hand.

Before relying on the setup, preview it against the real history (read-only):

```sh
npm ci --prefix release
CI_REPO=whexy/<name> GITHUB_TOKEN="$(gh auth token)" node release/release-please.mjs --dry-run
```

The first push after the bootstrap commit should open the `initial-version`
release PR. If it does not, land a commit whose body contains
`Release-As: 0.1.0-alpha.1`.

## Going stable (only when Wenxuan decides)

1. Set `versioning: default`, `prerelease: false` and `release-as: <x.y.z>`
   in the package config.
2. Merge the resulting release PR, then remove `release-as`.
3. In the same window, widen the cluster's image-updater constraint and
   `allow-tags` to stable versions. The alpha filter rejects stable tags.

Stable releases become GitHub's Latest release; container tags still never
float.
