# Every agent reads the same skills, linked into each agent's user-scope
# skill directory. A skill is a directory holding a SKILL.md, per the Agent
# Skills standard every harness implements.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.agents.skills;
  tree = (import ./build.nix { inherit pkgs; }).build cfg;

  # Each root is a real directory holding one link per skill directory, never
  # per file: Codex skips a skill whose SKILL.md is a link out of the
  # skill's directory and Muse Code rejects it, while Claude Code keeps
  # `synced/` in its root and Muse Code `.muse/` in its.
  roots = lib.unique (
    lib.sort lib.lessThan (
      lib.filter (root: root != null) (
        lib.mapAttrsToList (_: harness: harness.skillsRoot) config.dotfiles.agents.harnesses
      )
    )
  );
in
{
  options.dotfiles.agents.skills = {
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = ''
        Packages whose skills, at `share/skills/<name>/SKILL.md`, agents
        see. Only these are read, never the whole home profile.
      '';
    };
    local = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            source = lib.mkOption {
              type = lib.types.path;
              description = "The skill's directory.";
            };
            reason = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Why this skill is written here rather than taken from a package, when a tool it covers ships its own.";
            };
          };
        }
      );
      default = { };
      description = "Skills that come from this repository rather than a package.";
    };
    override = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            patches = lib.mkOption {
              type = lib.types.listOf lib.types.path;
              default = [ ];
              description = "Patches applied to the skill's directory with `patch -p1 --fuzz=0`.";
            };
            replace = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "A directory that stands in for the package's skill.";
            };
            ignore = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to hide the skill from agents.";
            };
            reason = lib.mkOption {
              type = lib.types.str;
              description = "Why the package's skill is not taken as it is.";
            };
          };
        }
      );
      default = { };
      description = ''
        Changes to a skill a package in `packages` provides: exactly one of
        `patches`, `replace` or `ignore`.
      '';
    };
    docs = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = ''
        Trees skills read by path, linked at
        `~/.local/share/agents/docs/<name>`. They are not registered as
        skills, so their contents are not checked.
      '';
    };
  };

  config = lib.mkIf config.dotfiles.agents.enable {
    assertions = lib.mapAttrsToList (name: o: {
      assertion =
        lib.length (
          lib.filter lib.id [
            (o.patches != [ ])
            (o.replace != null)
            o.ignore
          ]
        ) == 1;
      message = "dotfiles.agents.skills.override.${name} must set exactly one of patches, replace or ignore.";
    }) cfg.override;

    home.file =
      lib.genAttrs roots (_: {
        source = "${tree}/links";
        recursive = true;
      })
      // lib.mapAttrs' (
        name: _: lib.nameValuePair ".local/share/agents/docs/${name}" { source = "${tree}/docs/${name}"; }
      ) cfg.docs;

    # Home Manager cannot write a skill's link where an old link to a
    # directory, or a directory, still stands: it reports a collision, or
    # backs the path up by moving it, which fails inside the store and
    # otherwise leaves a copy of every skill beside the new links. So this
    # removes `~/.agents/skills` when it is one link, and empties every
    # directory in a root that holds a link into a generation's files, as
    # each skill linked file by file does: those links go, then every empty
    # directory under it. Entries holding no such link, Claude
    # Code's `synced/` among them, are not Home Manager's and stay.
    # Remove once every host has activated a generation that has this.
    home.activation.migrateSkillsDir = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      if [ -L "$HOME/.agents/skills" ]; then
        run rm $VERBOSE_ARG "$HOME/.agents/skills"
      fi
      for root in ${lib.concatMapStringsSep " " (root: ''"$HOME/${root}"'') roots}; do
        for entry in "$root"/*; do
          if [ -d "$entry" ] && [ ! -L "$entry" ] \
            && [ -n "$(find "$entry" -type l -lname '*-home-manager-files/*' -print -quit)" ]; then
            run find "$entry" -type l -lname '*-home-manager-files/*' -delete
            run find "$entry" -depth -type d -empty -delete
          fi
        done
      done
    '';
  };
}
