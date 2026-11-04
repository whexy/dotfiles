{
  pkgs,
  flake,
  inputs,
}:

# HyperFrames: a CLI that renders HTML/CSS/GSAP compositions to video,
# frame-exact, through a headless Chrome.
#
# The npm tarball already ships the compiled `dist/`, so nothing is built
# here. It carries no lockfile; packages/update generates package-lock.json
# from the tarball's package.json after `lockfileFilter`.
let
  inherit (pkgs) lib;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  version = "0.9.10";

  # devDependencies only serve upstream's monorepo; its `workspace:*` ones
  # cannot be resolved from the registry, and dist/ already bundles them.
  lockfileFilter = "del(.devDependencies)";

  # The init templates load this GSAP from a CDN, which makes every render
  # fetch it. Compositions copy this file instead and render offline.
  # update.py keeps it at the version the templates name.
  gsap = pkgs.fetchurl {
    url = "https://registry.npmjs.org/gsap/-/gsap-3.15.0.tgz";
    hash = "sha256-0uM60gLUgR6QhIg/f/mieWesQJXK71HKTJ0gaXolOxw=";
  };

  # The npm tarball bundles only three internal skills; the published agent
  # skills live in the repository.
  skills = pkgs.fetchFromGitHub {
    owner = "heygen-com";
    repo = "hyperframes";
    tag = "v${version}";
    sparseCheckout = [ "skills" ];
    hash = "sha256-BsNuqdTqEWMAJP/f1/CDT52Rkf5yxbgxIsWaW4Ke2xw=";
  };

  # A caller's own settings still win. The switches stop HyperFrames from
  # installing skills into every agent's global directories, phoning home,
  # and npm-installing optional packages into ~/.cache at run time.
  #
  # The Chrome HyperFrames downloads cannot find its libraries on NixOS, so
  # Linux renders with T3 Code's patched copy; Darwin keeps HyperFrames' own
  # download, which runs as is. /usr/lib/wsl/lib holds the WSL NVIDIA driver;
  # without it `render --gpu` silently falls back to libx264.
  wrapperArgs = [
    "--set-default"
    "HYPERFRAMES_SKIP_SKILLS"
    "1"
    "--set-default"
    "HYPERFRAMES_NO_TELEMETRY"
    "1"
    "--set-default"
    "HYPERFRAMES_NO_UPDATE_CHECK"
    "1"
    "--set-default"
    "HYPERFRAMES_NO_AUTO_INSTALL"
    "1"
    "--set-default"
    "HYPERFRAMES_FFMPEG_PATH"
    (lib.getExe' pkgs.ffmpeg "ffmpeg")
    "--set-default"
    "HYPERFRAMES_FFPROBE_PATH"
    (lib.getExe' pkgs.ffmpeg "ffprobe")
  ]
  ++ lib.optionals isLinux [
    "--set-default"
    "HYPERFRAMES_BROWSER_PATH"
    # T3's preview browser, read from the fork source rather than through
    # t3code-fork, which has no server on aarch64-linux.
    "${
      import ../t3code-fork/browser.nix {
        inherit pkgs;
        source = inputs.t3code-fork;
      }
    }/chrome-headless-shell"
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    "/usr/lib/wsl/lib"
  ];
in
pkgs.buildNpmPackage (finalAttrs: {
  pname = "hyperframes";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/hyperframes/-/hyperframes-${finalAttrs.version}.tgz";
    hash = "sha256-nrP2J7e9PwH4OJyVA98XahrsUWS+w3VQN3EMZzRyX0g=";
  };

  nodejs = pkgs.nodejs_22;
  npmDepsHash = "sha256-dVTvn7+s3aTxjo8Nf8e2jE46e+/FppMzIXhooeuAhn0=";

  # `init` copies its templates out of the store with their read-only modes,
  # then fails to rewrite them; the copies get their owner write bit back.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    ${lib.getExe pkgs.jq} ${lib.escapeShellArg lockfileFilter} package.json > package.json.new
    mv package.json.new package.json

    # Module file names change with every release, and the template copy
    # goes through whichever helper upstream currently uses, so the copy is
    # found by its arguments.
    copyTemplate='[A-Za-z_$][A-Za-z0-9_$]*\(templateDir, destDir[^;]*\);'
    init=$(grep -lE "$copyTemplate" dist/*.js)
    [ "$(printf '%s\n' "$init" | wc -l)" -eq 1 ]
    [ "$(grep -cE "$copyTemplate" "$init")" -eq 1 ]
    sed -Ei "s/$copyTemplate/& makeCopyWritable(templateDir, destDir);/" "$init"
    substituteInPlace "$init" \
      --replace-fail 'copyFileSync(src, dest);' \
        'copyFileSync(src, dest); makeCopyWritable(src, dest);'
    cat >> "$init" <<'EOF'
    function makeCopyWritable(src, dest) {
      const fs = require("node:fs");
      const path = require("node:path");
      fs.chmodSync(dest, fs.statSync(dest).mode | 0o200);
      if (fs.statSync(src).isDirectory()) {
        for (const entry of fs.readdirSync(src)) {
          makeCopyWritable(path.join(src, entry), path.join(dest, entry));
        }
      }
    }
    EOF
  '';

  dontNpmBuild = true;

  # sharp's prebuilt addon stays unpatched: it reaches its bundled libvips
  # through $ORIGIN and takes libstdc++ from Node, which already loaded it.
  # Growing libvips-cpp's RUNPATH with patchelf moves its .plt and crashes it.
  nativeBuildInputs = [ pkgs.makeWrapper ];

  postInstall = ''
    tar -xzf ${gsap} -O package/dist/gsap.min.js > gsap.min.js
    install -Dm444 gsap.min.js $out/share/hyperframes/vendor/gsap.min.js
    mkdir -p $out/share/skills
    cp -R ${skills}/skills/*/ $out/share/skills/
  '';

  postFixup = ''
    for program in hyperframes hyperframes-localize-fonts; do
      wrapProgram $out/bin/$program ${lib.escapeShellArgs wrapperArgs}
    done
  '';

  passthru = {
    gsap = "${finalAttrs.finalPackage}/share/hyperframes/vendor/gsap.min.js";
    gsapTarball = gsap;
    skillsSrc = skills;
    updater = flake.lib.updater {
      kind = "script";
      settings = { inherit lockfileFilter; };
      subpackages = [ "skillsSrc" ];
    };
  };

  meta = {
    description = "Render HTML/CSS/GSAP video compositions frame-exact";
    homepage = "https://github.com/heygen-com/hyperframes";
    changelog = "https://github.com/heygen-com/hyperframes/releases/tag/v${finalAttrs.version}";
    license = [
      lib.licenses.asl20
      # The vendored GSAP build.
      {
        fullName = "GSAP Standard No Charge License";
        url = "https://gsap.com/standard-license";
        free = false;
      }
    ];
    mainProgram = "hyperframes";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
