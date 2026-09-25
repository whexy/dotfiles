---
name: sandbox-repo-io
description: Move a repository into the code sandbox, work on it, and hand the changes back to GitHub through the GitHub tools. Use whenever a task needs a repository's code inside the sandbox, or needs sandbox changes turned into a branch or pull request.
---

# Getting code into and out of the sandbox

The sandbox runs commands and holds files, and it has **no GitHub
credentials**. You reach GitHub only through your GitHub tools outside it.
Code therefore enters the sandbox by clone or upload, and changes leave it as
data you read back and push with the GitHub tools.

Tool names below follow the GitHub MCP server (`get_file_contents`,
`create_branch`, `push_files`, `delete_file`, `create_pull_request`). Use
whatever equivalents you have.

## 1. Bring the code in

Work under `~/projects/<repo>`. `~/workspace` belongs to n8n workflow builds.

**Public repository:** clone it.

```sh
git clone --depth 1 --branch <base-branch> https://github.com/<owner>/<repo> ~/projects/<repo>
```

Drop `--depth 1` only if you need history (blame, bisect, log). If the
network is off, the clone fails fast; fall back to an upload.

**Private repository:** the sandbox cannot authenticate, so upload the code.

1. Prefer a tool that downloads the repository archive (tarball) for a ref.
   Write the archive into the sandbox, then unpack it:
   `mkdir -p ~/projects/<repo> && tar -xzf /tmp/<repo>.tar.gz -C ~/projects/<repo> --strip-components=1`.
2. The sandbox file API accepts up to **10 MB per file**. For a larger
   archive, write it in parts (`/tmp/<repo>.part-00`, `-01`, …) and join them:
   `cat /tmp/<repo>.part-* > /tmp/<repo>.tar.gz`. If your file tool only
   takes text, send base64 and decode with `base64 -d`.
3. With no archive tool, fetch only the files the task needs with
   `get_file_contents` and write them into the same paths. Say that you are
   working on a partial checkout.

Never put a GitHub token, or any credential other than the shared-space key
(see the `shared-space` skill), into a command or a file in the sandbox. If
a task seems to need one, stop and say so.

## 2. Pin the base before changing anything

```sh
cd ~/projects/<repo>
[ -d .git ] || { git init -q && git add -A && git commit -qm base; }   # uploaded trees have no .git
git rev-parse HEAD > /tmp/<repo>.base
git switch -c agent/<short-task-name>
```

`/tmp/<repo>.base` is what every later diff compares against. Record which
upstream commit or branch the code came from as well. You need it to create
the GitHub branch from the same point.

## 3. Check the change before handing it back

```sh
cd ~/projects/<repo>
git add -A
git status --short
git diff --cached --stat "$(cat /tmp/<repo>.base)"
```

- Run the project's tests and linters first, and report what you ran.
- Make sure no build output, dependencies (`node_modules`, `.venv`, `dist`),
  logs, or large or binary files are staged. Unstage them or add them to
  `.gitignore`.
- Do not change `.github/workflows/` or other CI configuration unless the task
  asks for it, and call it out if you do.

## 4. Hand the change back to GitHub

List exactly what changed:

```sh
git diff --cached --name-status --find-renames "$(cat /tmp/<repo>.base)"
```

Then, with the GitHub tools:

1. `create_branch`: `agent/<short-task-name>`, from the upstream commit the
   code came from. Never push to the default branch.
2. For `A` (added) and `M` (modified) paths, read each file's full content
   from the sandbox, then send all of them in one `push_files` call with a
   clear commit message.
3. For `D` (deleted) paths, `delete_file`. For `R` (renamed), push the new
   path and delete the old one.
4. Binary files cannot go through `push_files`. List them in the pull request
   instead of pushing them.
5. `create_pull_request` as a **draft**. The body covers what changed, why,
   the tests you ran with their results, and anything you could not verify.

For a large change, or when review matters more than a branch, also attach
the patch:

```sh
git commit -qm "<message>"
git format-patch "$(cat /tmp/<repo>.base)" --stdout > /tmp/<repo>.patch
```

Read `/tmp/<repo>.patch` back, and include it or summarise it in the pull
request.

## 5. Before finishing

- The sandbox is deleted after the task, so anything not pushed or reported
  is lost.
- Report the branch, the pull request link, and which files were skipped
  (binary or oversized) and why.
