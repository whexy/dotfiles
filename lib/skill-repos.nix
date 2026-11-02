# Each directory under skills/ names a repository published for `npx skills`,
# pinned by its sources.json, and becomes a package of the skills taken from
# it at share/skills. The `skills` CLI installs them from the pinned source,
# so agents see exactly what `npx skills add` gives.
{ inputs, updater }:
pkgs:
let
  inherit (pkgs) lib;
  root = ../skills;

  repo =
    name:
    let
      dir = root + "/${name}";
      declaration = import dir;
      pins = dir + "/sources.json";
      sources = if builtins.pathExists pins then lib.importJSON pins else null;
      picks = declaration.skills or null;
      github = "https://github.com/${declaration.owner}/${declaration.repo}";
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = name;
      version = if sources == null then "0" else sources.version;
      src =
        if sources == null then
          # Evaluates, so the updater can pin it; says what to do when built.
          pkgs.runCommand "${name}-unpinned" { } ''
            echo "skills/${name} is not pinned yet; run: nix run .#update -- ${name}" >&2
            exit 1
          ''
        else
          pkgs.fetchFromGitHub {
            inherit (declaration) owner repo;
            inherit (sources) rev hash;
          };

      nativeBuildInputs = [ inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.skills ];
      DISABLE_TELEMETRY = "1";

      buildCommand = ''
        export HOME=$TMPDIR/home
        mkdir -p $HOME project
        cd project
        skills add $src --agent universal --copy --yes \
          --skill ${lib.escapeShellArgs (if picks == null then [ "*" ] else picks)} </dev/null
        for skill in ${lib.escapeShellArgs (if picks == null then [ ] else picks)}; do
          test -f .agents/skills/$skill/SKILL.md ||
            { echo "${declaration.owner}/${declaration.repo} has no skill $skill" >&2; exit 1; }
        done
        mkdir -p $out/share
        cp -r .agents/skills $out/share/skills
      '';

      passthru.updater = updater (
        if builtins.pathExists (dir + "/update.py") then
          {
            kind = "script";
            settings = declaration;
          }
        else
          {
            kind = "github-branch";
            inherit (declaration) owner repo;
          }
      );

      meta = {
        description = "Agent skills from ${declaration.owner}/${declaration.repo}";
        homepage = github;
        changelog = "${github}/commits/${if sources == null then "HEAD" else sources.rev}";
        platforms = lib.platforms.all;
      };
    };
in
lib.genAttrs (lib.attrNames (
  lib.filterAttrs (_: type: type == "directory") (builtins.readDir root)
)) repo
