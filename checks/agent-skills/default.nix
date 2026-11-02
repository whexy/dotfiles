# Builds every skill in the repo at once, as no single home does, so a patch
# an upstream bump breaks or a skill with bad frontmatter fails CI before any
# host switches. `expected` lists every skill agents can see; a change to what
# agents see must change it too. A skill repository's names come from its
# build: its package already says what it takes.
{
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  inherit (pkgs) lib;
  skills = import ../../modules/home/agents/skill-tree/build.nix { inherit pkgs; };

  # Every feature that adds skills declares them in a skills.nix beside its
  # module, so a new feature is built here without being listed.
  features = map (file: import file { inherit pkgs perSystem flake; }) (
    flake.lib.importDir ../../modules/home { pattern = "/skills.nix"; }
  );
  merge =
    key:
    lib.foldl' (
      acc: feature:
      let
        new = feature.${key} or { };
        both = lib.intersectLists (lib.attrNames acc) (lib.attrNames new);
      in
      assert lib.assertMsg (both == [ ]) "${key}.${toString both} comes from two skills.nix files";
      acc // new
    ) { } features;
  spec = {
    packages = lib.concatMap (feature: feature.packages or [ ]) features;
    local = merge "local";
    override = merge "override";
    docs = merge "docs";
  };
  tree = skills.build spec;
  # The skill repositories every agent takes.
  repos = (import ../../modules/home/agents/skills.nix { inherit pkgs perSystem; }).packages;

  expected = pkgs.writeText "agent-skills-expected" ''
    asc
    broll
    cf-cli
    council
    deploy-to-cluster
    design
    draw
    explain
    git-commit
    iphone-use
    iphone-use-setup
    knowledge
    nix-blueprint
    op-sa
    reverse-engineer-anything
    review-loop
    ship-pr
    spark
    t3-setup
    transcribe
    video-edit
    web-preview
    wechat
  '';
in
pkgs.runCommand "agent-skills"
  {
    # The skill sources are the same on every system; one is enough.
    meta.platforms = [ "x86_64-linux" ];
  }
  ''
    {
      cat ${expected}
      ${lib.concatMapStrings (repo: "ls ${repo}/share/skills\n") repos}
    } | LC_ALL=C sort >expected
    diff -u expected ${tree}/names
    for name in ${lib.concatStringsSep " " (lib.attrNames spec.docs)}; do
      test -e ${tree}/docs/$name/.
    done
    touch $out
  ''
