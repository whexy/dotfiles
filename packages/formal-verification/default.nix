# pstack's formal-verification skills, with the tools statechart's runner
# needs. Left alone it installs TLC and Java with mise, which no host has, so
# its wrapper names the ones from nixpkgs; a caller's own TLA2TOOLS or JAVA
# still wins.
{
  flake,
  pkgs,
  pname,
}:
let
  inherit (pkgs) lib;
in
(flake.lib.skillRepo {
  inherit pkgs pname;
  owner = "cursor";
  repo = "plugins";
  # create-formal-verification-skill links to the other two by relative
  # path.
  skills = [
    "create-formal-verification-skill"
    "maintain-formal-verification-skill"
    "statechart"
  ];
  # pstack takes from the same repository.
  pins = ../pstack/sources.json;
}).overrideAttrs
  (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.makeWrapper ];
    # statechart.ts is run by the Node on PATH, which must strip types.
    buildCommand = old.buildCommand + ''
      wrapProgram $out/share/skills/statechart/scripts/statechart \
        --prefix PATH : ${lib.makeBinPath [ pkgs.nodejs ]} \
        --set-default TLA2TOOLS ${pkgs.tlaplus}/share/java/tla2tools.jar \
        --set-default JAVA ${lib.getExe' pkgs.jre_headless "java"}
    '';
    # The pin is pstack's, whose updater builds this package when it moves.
    passthru = old.passthru // {
      updater = null;
    };
  })
