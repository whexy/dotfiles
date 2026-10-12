{
  pkgs,
  inputs,
  system,
}:

# REA (Reverse Engineer Anything): a CLI and the stdio MCP server `rea mcp`.
#
# The npm tarball already ships the compiled `dist/`, so nothing is built
# here. It carries no lockfile; package-lock.json is generated from the
# tarball's package.json after the postPatch edit below, with
#   npm install --package-lock-only --ignore-scripts
let
  inherit (pkgs) lib stdenv;
  unstable = inputs.nixpkgs-unstable.legacyPackages.${system};

  # REA admits only Ghidra 12.1.x, which the release branch does not have yet.
  inherit (unstable) ghidra;
  # The JDK Ghidra itself runs on; REA also needs its javac to compile the
  # bridge.
  jdk = unstable.openjdk21;
in
pkgs.buildNpmPackage (finalAttrs: {
  pname = "rea-agents";
  version = "6.4.0";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${finalAttrs.version}.tgz";
    hash = "sha512-Vj1zWfSlna5bphGoaoI/TcVBuYvze9u+OyPC3Shz8YkBqaCTqB4COnnRoX7XDwMpwI24ZlFEel2yEj0k8LTWEQ==";
  };

  nodejs = pkgs.nodejs_24;
  npmDepsHash = "sha256-aMD66LEDaVjyDrdaaSQA2FjdAUltdj+RZH8W8xNIdNo=";

  # devDependencies only serve upstream's source checkout, and the vitepress
  # override belongs to one of them.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    ${lib.getExe pkgs.jq} 'del(.devDependencies, .overrides)' package.json > package.json.new
    mv package.json.new package.json
  '';

  dontNpmBuild = true;

  # node-pty's prebuilt Linux addon links against libstdc++.
  nativeBuildInputs = [
    pkgs.makeWrapper
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;
  buildInputs = lib.optional stdenv.hostPlatform.isLinux stdenv.cc.cc.lib;

  # A caller's own GHIDRA_INSTALL_DIR or JAVA_HOME still wins.
  postFixup = ''
    for program in rea rea-agents; do
      wrapProgram $out/bin/$program \
        --set-default GHIDRA_INSTALL_DIR ${ghidra}/lib/ghidra \
        --set-default JAVA_HOME ${jdk}
    done
  '';

  meta = {
    description = "Reverse engineer anything with agents, from app behavior down to native binaries";
    homepage = "https://github.com/morluto/rea";
    license = lib.licenses.mit;
    mainProgram = "rea";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
