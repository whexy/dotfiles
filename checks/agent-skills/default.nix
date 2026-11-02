# Builds every skill in the repo at once, as no single home does, so a patch
# an upstream bump breaks or a skill with bad frontmatter fails CI before any
# host switches. `expected` lists every skill agents can see; a change to what
# agents see must change it too.
{ pkgs, perSystem, ... }:
let
  inherit (pkgs) lib;
  agents = ../../modules/home/agents;
  skills = import (agents + "/build-skills.nix") { inherit pkgs; };
  video = (import (agents + "/video/home.nix") { inherit pkgs perSystem; }).skills;
  cloudflare = import (agents + "/cloudflare/skills.nix") { inherit (perSystem.self) cf; };
  iphone = import (agents + "/iphone/skills.nix") { iphoneUse = perSystem.self.iphone-use; };

  tree = skills.build {
    packages = [
      perSystem.self.transcribe
      perSystem.self.wechat-cli
      perSystem.self.rea-agents
    ]
    ++ cloudflare.packages
    ++ iphone.packages
    ++ video.packages;
    local =
      lib.mapAttrs (name: _: { source = agents + "/skills/${name}"; }) (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir (agents + "/skills"))
      )
      // video.local
      // {
        spark.source = agents + "/spark/skill";
        asc.source = agents + "/asc/skill";
      };
    override = cloudflare.override // iphone.override // video.override;
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
