---
name: add-agent-skill
description: Add, change, hide, or remove a skill that agents see through the dotfiles repo - a local skill, a skill a package ships, a skill repository under skills/, or an override of an upstream skill. Use when the set of skills in ~/.agents/skills or ~/.claude/skills should change.
---

# Adding a skill to dotfiles

A skill is a directory that holds a `SKILL.md`. Home Manager builds every
skill a home enables into one tree and links each one into
`~/.agents/skills`, `~/.claude/skills` and `~/.config/muse/skills`. Never
put a skill in those directories by hand.

Every skill comes from one of three sources. Pick the source first:

| The skill                                              | Source                                                                        |
| ------------------------------------------------------ | ----------------------------------------------------------------------------- |
| is general, so anyone could use it                     | [whexy/wxstack](https://github.com/whexy/wxstack), pinned at `skills/wxstack` |
| is published in someone else's `npx skills` repository | a new skill repository under `skills/`                                        |
| teaches one CLI that a package here builds             | that package, at `$out/share/skills`                                          |
| names our hosts, credentials or infrastructure         | a local skill, in `modules/home/agents/skills/<name>/`                        |
| belongs to one feature and drives several of its tools | a local skill beside that feature, such as `agentic-tooling/video/skills/`    |

A skill that only this repository's work needs, such as a host procedure,
is not an agent skill. Put it in `.agents/skills/` of this repo, like this
skill.

## The option

Each source ends up in `dotfiles.agents.skills`. Modules set it; every value
merges.

| Option                    | Takes                                          | Use it for                                                                                |
| ------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `packages`                | packages with `share/skills/<name>/SKILL.md`   | skill repositories and tool packages; every skill in them shows                           |
| `local.<name>.source`     | a directory in this repo                       | a skill written here                                                                      |
| `local.<name>.reason`     | text                                           | set when the skill stands in for one a tool would install itself, as `asc` and `spark` do |
| `override.<name>.patches` | patch files, applied with `patch -p1 --fuzz=0` | a small change to a package's skill                                                       |
| `override.<name>.replace` | a directory                                    | a package's skill that must be rewritten here                                             |
| `override.<name>.ignore`  | `true`                                         | a package's skill that agents must not see                                                |
| `override.<name>.reason`  | text, required                                 | why the package's skill is not taken as it is                                             |
| `docs.<name>`             | a path                                         | a tree that a skill reads by path, at `~/.local/share/agents/docs/<name>`                 |

An `override` sets exactly one of `patches`, `replace` or `ignore`, and only
names a skill that a listed package provides. Never change an upstream skill
any other way: copy it into git and you lose its updates.

## Add a local skill

1. Create `modules/home/agents/skills/<name>/SKILL.md`. The frontmatter
   `name` is the directory name; `description` says what the skill is for
   and when to use it. Agents choose skills by that description alone.
2. Add `<name>` to the `expected` list in `checks/agent-skills/default.nix`,
   in sorted order.

`modules/home/agents/skills.nix` takes every directory there, so no Nix
changes. A skill beside a feature goes in that feature's `skills.nix` as
`local.<name>.source = ./skills/<name>;` instead.

## Add a skill repository

1. Create `skills/<repo>/default.nix`:

   ```nix
   {
     owner = "t3dotgg";
     repo = "tstack";
     skills = [ "sol-loop" ]; # leave out to take every skill
   }
   ```

2. `git add skills/<repo>`, then pin it:

   ```sh
   nix run .#update -- <repo>
   ```

   This writes `sources.json`. An unpinned repository fails the build, so pin
   each one before you add the next.

Every agent gets every repository. The check reads the repository's names
from its build, so `expected` does not change. When a skill moves from local
to wxstack, delete the local copy in the same change: two sources for one
name fail the build.

## Add a package's skills

A package ships its skills at `$out/share/skills/<name>/SKILL.md`.

- **Our package:** keep the skills in `packages/<pname>/skills/`, leave that
  directory out of `src` with `lib.fileset`, and copy it in at install
  (`cp -r ${./skills} $out/share/skills`). Then a skill edit does not rerun
  the tool's checks. See `packages/transcribe/default.nix`.
- **A third-party tool:** copy every skill upstream publishes into
  `share/skills`, and leave upstream's own copy where its code reads it. See
  `packages/iphone-use/default.nix`.

Then give the feature that installs the CLI a `skills.nix` beside its module:

```nix
# The skills <tool> ships, as a `dotfiles.agents.skills` value; the home
# module and checks/agent-skills both take it from here.
{ perSystem, ... }:
{
  packages = [ perSystem.self.<pname> ];
}
```

Import it in the same `lib.mkIf` that adds the CLI to `home.packages`, so a
home sees the skill only where it has the tool:

```nix
dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem; };
```

`skills.nix` takes no module arguments, only some of
`{ pkgs, perSystem, flake }`. `checks/agent-skills` finds every `skills.nix`
under `modules/home` itself; add the new names to `expected`, and an
`override.<name>.ignore` for each upstream skill agents must not see.

## Change a package's skill

To patch it, write the patch against the skill's own directory, so paths
read `a/SKILL.md`:

```sh
cp -r $(nix build .#<pname> --print-out-paths --no-link)/share/skills/<name> a
cp -r a b && chmod -R u+w b
# edit b/
diff -ru a b > modules/home/<feature>/<name>-skill.patch
```

```nix
override.<name> = {
  patches = [ ./<name>-skill.patch ];
  reason = "Why our hosts need it changed.";
};
```

A patch must apply with no fuzz. When an upstream bump breaks it, the
nightly update holds back that package alone; refresh the patch.

Use `replace = ./<dir>;` when most of the skill changes, and
`ignore = true;` to hide it. To let a skill read hidden upstream skills by
path, also set `docs.<name>` to their tree, as
`modules/home/agentic-tooling/video/skills.nix` does for `broll`. A `docs`
tree must hold no skill that agents also see.

## Verify

`git add` new files first: the flake sees only tracked files.

```sh
nix build .#checks.x86_64-linux.agent-skills
```

It builds every skill in the repo, then diffs their names against
`expected` and the skill repositories. It fails when:

- two sources give one name
- a listed package has no `share/skills`
- an override names no package skill, or a patch does not apply
- a `docs` tree holds a skill agents see
- a `SKILL.md` has a frontmatter `name` other than its directory, or no
  `description`
- a skill is named `synced`, which Claude Code keeps for account skills

Run `just check` for formatting, then switch the home to see the skill in
the agent.
