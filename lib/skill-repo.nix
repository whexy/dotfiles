# A repository published for `npx skills`, pinned by `pins` (its sources.json),
# as a package of the skills taken from it at share/skills. The `skills` CLI
# installs them from the pinned source, so agents see exactly what
# `npx skills add` gives, with the files they link to outside themselves.
{ inputs, updater }:
{
  pkgs,
  pname,
  owner,
  repo,
  # The names to take, as `npx skills add --skill` takes them; null takes all.
  skills ? null,
  pins,
  # Packages that read these pins too, built when they move.
  alsoBuild ? [ ],
}:
let
  inherit (pkgs) lib;
  sources = if builtins.pathExists pins then lib.importJSON pins else null;
  github = "https://github.com/${owner}/${repo}";
in
pkgs.stdenvNoCC.mkDerivation {
  inherit pname;
  version = if sources == null then "0" else sources.version;
  src =
    if sources == null then
      # Evaluates, so the updater can pin it; says what to do when built.
      pkgs.runCommand "${pname}-unpinned" { } ''
        echo "packages/${pname} is not pinned yet; run: nix run .#update -- ${pname}" >&2
        exit 1
      ''
    else
      pkgs.fetchFromGitHub {
        inherit owner repo;
        inherit (sources) rev hash;
      };

  nativeBuildInputs = [
    inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.skills
    pkgs.python3
  ];
  DISABLE_TELEMETRY = "1";

  buildCommand = ''
    export HOME=$TMPDIR/home
    mkdir -p $HOME project
    cd project
    skills add $src --agent universal --copy --yes \
      --skill ${lib.escapeShellArgs (if skills == null then [ "*" ] else skills)} </dev/null
    for skill in ${lib.escapeShellArgs (if skills == null then [ ] else skills)}; do
      test -f .agents/skills/$skill/SKILL.md ||
        { echo "${owner}/${repo} has no skill $skill" >&2; exit 1; }
    done
    mkdir -p $out/share
    cp -r .agents/skills $out/share/skills
    chmod -R u+w $out/share/skills
    python3 ${./skill-repo-links.py} $src $out/share
  '';

  passthru.updater = updater (
    {
      kind = "github-branch";
      inherit owner repo;
    }
    // lib.optionalAttrs (alsoBuild != [ ]) { inherit alsoBuild; }
  );

  meta = {
    description = "Agent skills from ${owner}/${repo}";
    homepage = github;
    changelog = "${github}/commits/${if sources == null then "HEAD" else sources.rev}";
    platforms = lib.platforms.all;
  };
}
