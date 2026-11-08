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
  skills = flake.lib.skillRepo {
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
  };
in
pkgs.runCommand "${pname}-${skills.version}"
  {
    inherit pname;
    inherit (skills) version meta;
    passthru = skills.passthru // {
      # The pin is pstack's, whose updater builds this package when it moves.
      updater = null;
    };
    nativeBuildInputs = [ pkgs.makeWrapper ];
  }
  ''
    cp -r ${skills} $out
    chmod -R u+w $out
    # statechart.ts is run by the Node on PATH, which must strip types.
    wrapProgram $out/share/skills/statechart/scripts/statechart \
      --prefix PATH : ${lib.makeBinPath [ pkgs.nodejs ]} \
      --set-default TLA2TOOLS ${pkgs.tlaplus}/share/java/tla2tools.jar \
      --set-default JAVA ${lib.getExe' pkgs.jre_headless "java"}
  ''
