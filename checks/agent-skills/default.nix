# Builds every skill in the repo at once, as no single home does, so a patch
# an upstream bump breaks or a skill with bad frontmatter fails CI before any
# host switches. `expected` lists every skill agents can see; a change to what
# agents see must change it too.
{ pkgs, perSystem, ... }:
let
  inherit (pkgs) lib;
  agents = ../../modules/home/agents;
  skills = import (agents + "/build-skills.nix") { inherit pkgs; };
  video = import (agents + "/video/home.nix") { inherit pkgs perSystem; };
  iphoneUse = perSystem.self.iphone-use;

  tree = skills.build {
    packages = [
      (skills.fromPaths "rea-agents" {
        reverse-engineer-anything = "${perSystem.self.rea-agents}/lib/node_modules/rea-agents/skills/reverse-engineer-anything";
      })
      (skills.fromPaths "iphone-use" {
        iphone-use = "${iphoneUse}/share/iphone-use/skills/iphone-use";
        iphone-use-setup = "${iphoneUse}/share/iphone-use/skills/iphone-use-setup";
      })
      (skills.fromPaths "cf" { cf-cli = perSystem.self.cf.skill; })
    ];
    local =
      lib.mapAttrs (name: _: { source = agents + "/skills/${name}"; }) (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir (agents + "/skills"))
      )
      // lib.mapAttrs (_: source: { inherit source; }) video.skills
      // {
        spark.source = agents + "/spark/skill";
        asc.source = agents + "/asc/skill";
      };
    override = {
      iphone-use-setup.replace = agents + "/iphone/iphone-use-setup";
      cf-cli.patches = [ (agents + "/cloudflare/cf-cli-skill.patch") ];
    };
    inherit (video) docs;
  };

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
    diff -u ${expected} ${tree}/names
    for name in ${lib.concatStringsSep " " (lib.attrNames video.docs)}; do
      test -e ${tree}/docs/$name/.
    done
    touch $out
  ''
