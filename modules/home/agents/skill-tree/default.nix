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

  # Claude Code scans only `~/.claude/skills` and reserves `synced/` there
  # for skills it downloads from the account, so every root holds one real
  # directory per skill rather than being a link itself.
  roots = [
    ".agents/skills"
    ".claude/skills"
    ".config/muse/skills"
  ];
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
        `~/.local/share/video-edit/docs/<name>`. They are not registered as
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
        source = "${tree}/skills";
        recursive = true;
      })
      // lib.mapAttrs' (
        name: _:
        lib.nameValuePair ".local/share/video-edit/docs/${name}" { source = "${tree}/docs/${name}"; }
      ) cfg.docs;

    # Activation cannot move a root, or a skill in one, from a link to a
    # directory: Home Manager tries to back the old link up by moving its
    # read-only store target, or reads through it and reports every file
    # as a collision, and dies before any link is written. So this removes
    # `~/.agents/skills` when it is one link, and in every root each skill
    # that links into a generation's files. Other entries, Claude Code's
    # `synced/` among them, are not Home Manager's and stay.
    # Remove once every host has activated a generation that has this.
    home.activation.migrateSkillsDir = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      if [ -L "$HOME/.agents/skills" ]; then
        run rm $VERBOSE_ARG "$HOME/.agents/skills"
      fi
      for root in ${lib.concatMapStringsSep " " (root: ''"$HOME/${root}"'') roots}; do
        for entry in "$root"/*; do
          if [ -L "$entry" ]; then
            case "$(readlink "$entry")" in
              *-home-manager-files/*) run rm $VERBOSE_ARG "$entry" ;;
            esac
          fi
        done
      done
    '';
  };
}
