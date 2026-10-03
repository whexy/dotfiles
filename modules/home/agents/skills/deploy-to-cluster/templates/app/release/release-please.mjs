import { readFile } from "node:fs/promises";
import { GitHub, Manifest } from "release-please";
import { githubToken } from "./github-app.mjs";

const dryRun = process.argv.includes("--dry-run");
const [owner, repo] = (process.env.CI_REPO ?? "").split("/");
if (!owner || !repo) throw new Error("Set CI_REPO to <owner>/<name>");
const branch = process.env.CI_REPO_DEFAULT_BRANCH || "main";
if (
  !dryRun &&
  process.env.CI_PIPELINE_EVENT !== "push" &&
  process.env.CI_PIPELINE_EVENT !== "manual"
) {
  throw new Error(
    "Release preparation requires a default-branch push or manual CI run",
  );
}
if (!dryRun && process.env.CI_COMMIT_BRANCH !== branch) {
  throw new Error(`Release preparation requires the ${branch} branch`);
}
const github = await GitHub.create({ owner, repo, token: await githubToken() });
if (dryRun) {
  // Preview the unmerged configuration against the real default-branch history.
  const remote = github.getFileContentsOnBranch.bind(github);
  github.getFileContentsOnBranch = async (path, ref) => {
    if (
      path !== "release-please-config.json" &&
      path !== ".release-please-manifest.json"
    ) {
      return remote(path, ref);
    }
    const parsedContent = await readFile(
      new URL(`../${path}`, import.meta.url),
      "utf8",
    );
    return {
      parsedContent,
      content: Buffer.from(parsedContent).toString("base64"),
      sha: "local",
    };
  };
}
let manifest = await Manifest.fromManifest(github, branch);
if (dryRun) {
  console.log("Candidate releases:", await manifest.buildReleases());
  console.log("Candidate release PRs:", await manifest.buildPullRequests());
} else {
  console.log("Created draft releases:", await manifest.createReleases());
  // Reload after tagging so the next PR starts after the release just created.
  manifest = await Manifest.fromManifest(github, branch);
  console.log(
    "Created or updated release PRs:",
    await manifest.createPullRequests(),
  );
}
