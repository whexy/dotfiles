{
  pkgs,
  inputs,
  flake,
  system,
}:

# REA (Reverse Engineer Anything): a CLI and the stdio MCP server `rea mcp`.
#
# The npm tarball already ships the compiled `dist/`, so nothing is built
# here. It carries no lockfile; packages/update generates package-lock.json
# from the tarball's package.json after `lockfileFilter`.
let
  inherit (pkgs) lib stdenv;
  unstable = inputs.nixpkgs-unstable.legacyPackages.${system};

  # REA admits only Ghidra 12.1.x, which the release branch does not have yet.
  inherit (unstable) ghidra;
  # The JDK Ghidra itself runs on; REA also needs its javac to compile the
  # bridge.
  jdk = unstable.openjdk21;

  # devDependencies only serve upstream's source checkout, and the vitepress
  # override belongs to one of them.
  lockfileFilter = "del(.devDependencies, .overrides)";

  # frida backs REA's Frida tools. Its install script runs prebuild-install,
  # which downloads this addon unless it finds the archive, under its release
  # file name, in the dependency's local-prebuilds directory.
  prebuilds.frida = {
    urlTemplate = "https://github.com/frida/frida/releases/download/{version}/frida-v{version}-napi-v8-{platform}.tar.gz";
    platforms = {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
    };
  };
  fridaPin = (lib.importJSON ./sources.json).frida;
  fridaPrebuild = pkgs.fetchurl {
    url =
      builtins.replaceStrings
        [ "{version}" "{platform}" ]
        [
          fridaPin.version
          prebuilds.frida.platforms.${system}
        ]
        prebuilds.frida.urlTemplate;
    hash = fridaPin.hashes.${system};
  };
  fridaPrebuilds = pkgs.linkFarm "frida-prebuilds" [
    {
      inherit (fridaPrebuild) name;
      path = fridaPrebuild;
    }
  ];
in
pkgs.buildNpmPackage (finalAttrs: {
  pname = "rea-agents";
  version = "6.8.0";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${finalAttrs.version}.tgz";
    hash = "sha256-jVQux2qcs1BYS2CmycCIcG/4EtW7WwlMIMlbbcJWmLs=";
  };

  nodejs = pkgs.nodejs_24;
  npmDepsHash = "sha256-XGu4uNmzDBjm3eE3PXpJGBcz7+vrZK1PnRhJihIQNHo=";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    ${lib.getExe pkgs.jq} ${lib.escapeShellArg lockfileFilter} package.json > package.json.new
    mv package.json.new package.json
  '';

  dontNpmBuild = true;

  env.npm_config_frida_local_prebuilds = fridaPrebuilds;

  # node-pty's prebuilt Linux addon links against libstdc++.
  nativeBuildInputs = [
    pkgs.makeWrapper
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;
  buildInputs = lib.optional stdenv.hostPlatform.isLinux stdenv.cc.cc.lib;

  # A caller's own settings still win. Sandboxed Linux tools fall back to
  # /usr/bin/prlimit, which NixOS does not have.
  postFixup =
    let
      prlimit = lib.getExe' pkgs.util-linux "prlimit";
      prlimitFlags = lib.optionalString stdenv.hostPlatform.isLinux (
        lib.concatMapStrings (tool: " --set-default REA_${tool}_PRLIMIT_COMMAND ${prlimit}") [
          "EVM"
          "FIRMWARE"
          "JAVASCRIPT"
        ]
      );
    in
    ''
      for program in rea rea-agents; do
        wrapProgram $out/bin/$program \
          --set-default GHIDRA_INSTALL_DIR ${ghidra}/lib/ghidra \
          --set-default JAVA_HOME ${jdk}${prlimitFlags}
      done
    '';

  passthru = {
    inherit fridaPrebuild;
    updater = flake.lib.updater {
      kind = "npm";
      inherit lockfileFilter prebuilds;
    };
  };

  meta = {
    description = "Reverse engineer anything with agents, from app behavior down to native binaries";
    homepage = "https://github.com/morluto/rea";
    changelog = "https://github.com/morluto/rea/releases/tag/rea-agents-${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "rea";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
