{ pkgs, ... }:

# cf, Cloudflare's unified CLI for its public API and Workers projects
# (https://developers.cloudflare.com/cf/). nixpkgs' `cloudflare-cli` is an
# unrelated community tool, and Wrangler and cloudflared are not this CLI.
#
# The npm tarball already ships the compiled `dist/`, so nothing is built
# here. It carries no lockfile; package-lock.json is generated from the
# tarball's package.json after the postPatch edit below, with
#   npm install --package-lock-only --ignore-scripts
let
  inherit (pkgs) lib stdenv;

  # Cloudflare's agent skill for cf. The skills repository has no releases;
  # take the commit current when bumping cf.
  skills = pkgs.fetchFromGitHub {
    owner = "cloudflare";
    repo = "skills";
    rev = "1a33048817d06df12882cb881dfc754e7039954a";
    sparseCheckout = [ "skills/cf-cli" ];
    hash = "sha256-QJY8p6Ck33R3f5XxyBqh6LRgBWYFy+r82a9KB+lAfdw=";
  };
in
pkgs.buildNpmPackage (finalAttrs: {
  pname = "cf";
  version = "1.0.0-beta.26";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/cf/-/cf-${finalAttrs.version}.tgz";
    hash = "sha512-StQUwvWubehIWMTqlUbfRNuUgO9qzE4ns7AMa0NbE2eJrOV32E9DwZxfxhqu4aADbE9kKXOt/XuqDC3mM3gC3w==";
  };

  # engines: ^22.23 || ^24.22 || ^26.12; the Darwin branch's nodejs_24 is
  # still 24.21.
  nodejs = pkgs.nodejs_22;
  npmDepsHash = "sha256-GkQpuyclr1Qmh0wm8ubWy5IiUcOf95SQzONTeLpiN5g=";

  # devDependencies only serve upstream's monorepo, and dist/ bundles them.
  #
  # Nix owns this copy, so the daily update notice, which tells the user to
  # `npm install --global cf@latest`, would only install a second one. The
  # check runs only in a terminal and has no switch; stubbing its module
  # turns it off. The module's file name changes with every release.
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    ${lib.getExe pkgs.jq} 'del(.devDependencies)' package.json > package.json.new
    mv package.json.new package.json

    updateCheck=$(grep -l 'as maybeStartBackgroundUpdateCheck' dist/update-check-*.mjs)
    [ "$(printf '%s\n' "$updateCheck" | wc -l)" -eq 1 ]
    cat > "$updateCheck" <<'EOF'
    export function getUpdateNotice() {}
    export function maybeStartBackgroundUpdateCheck() {}
    EOF
  '';

  dontNpmBuild = true;

  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeWrapper
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;

  # `cf dev` runs workerd, whose prebuilt binary expects an FHS loader. Only
  # workerd is patched: sharp's prebuilt addon reaches its bundled libvips
  # through $ORIGIN, and patchelf moves libvips-cpp's .plt and crashes it.
  dontAutoPatchelf = true;

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    for shell in bash fish zsh; do
      HOME=$TMPDIR $out/bin/cf complete $shell > cf.$shell
    done
    installShellCompletion --cmd cf --bash cf.bash --fish cf.fish --zsh cf.zsh
  '';

  postFixup =
    lib.optionalString stdenv.hostPlatform.isLinux ''
      autoPatchelf $out/lib/node_modules/cf/node_modules/{workerd,@cloudflare/workerd-*}
    ''
    # Upstream sends usage telemetry unless told not to, and remembers an
    # opt-out only per machine. A caller's own setting still wins.
    + ''
      for program in cf cloudflare; do
        wrapProgram $out/bin/$program --set-default CF_SEND_TELEMETRY false
      done
    '';

  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
  doInstallCheck = true;

  passthru.skill = "${skills}/skills/cf-cli";

  meta = {
    description = "Cloudflare's CLI for the Cloudflare API and Workers projects";
    homepage = "https://developers.cloudflare.com/cf/";
    changelog = "https://github.com/cloudflare/cf/releases";
    license = with lib.licenses; [
      mit
      asl20
    ];
    mainProgram = "cf";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
