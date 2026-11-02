# Builds the tree agents see from a `dotfiles.agents.skills` value. A plain
# function of pkgs, so checks/agent-skills builds every skill in the repo
# without evaluating a home.
{ pkgs }:
let
  inherit (pkgs) lib;
in
{
  build =
    {
      packages ? [ ],
      local ? { },
      override ? { },
      docs ? { },
    }:
    pkgs.runCommand "agent-skills"
      {
        nativeBuildInputs = [
          (pkgs.python3.withPackages (p: [ p.pyyaml ]))
          pkgs.patch
        ];
        spec = builtins.toJSON {
          packages = lib.unique (map toString packages);
          local = lib.mapAttrs (_: skill: skill.source) local;
          override = lib.mapAttrs (_: o: {
            patches = o.patches or [ ];
            replace = o.replace or null;
            ignore = o.ignore or false;
          }) override;
          inherit docs;
        };
        passAsFile = [ "spec" ];
      }
      ''
        python3 ${./build-skills.py} "$specPath" "$out"
      '';
}
