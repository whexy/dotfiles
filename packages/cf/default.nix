{ pkgs, flake, ... }:

# cf, Cloudflare's unified CLI for its public API and Workers projects
# (https://developers.cloudflare.com/cf/). nixpkgs' `cloudflare-cli` is an
# unrelated community tool, and Wrangler and cloudflared are not this CLI.
let
  inherit (pkgs) lib stdenv;

  # devDependencies only serve upstream's monorepo, and dist/ bundles them.
  lockfileFilter = "del(.devDependencies)";
  npm = flake.lib.npmTarball {
    inherit pkgs lockfileFilter;
    lockfile = ./package-lock.json;
  };

  # Cloudflare's agent skill for cf, which the npm tarball does not ship. The
  # skills repository has no releases; it moves to the default branch's head
  # whenever cf moves.
  skills = pkgs.fetchFromGitHub {
    owner = "cloudflare";
    repo = "skills";
    rev = "cbf893b954222276bf1af57e5f23379231e0efb9";
    sparseCheckout = [ "skills/cf-cli" ];
    hash = "sha256-6QcGABT4vqNFuVDnrpSxEZSM5JGELGpueCeOqXVICmg=";
  };
in
pkgs.buildNpmPackage (finalAttrs: {
  pname = "cf";
  version = "1.0.0-beta.30";

  src = pkgs.fetchurl {
    url = "https://registry.npmjs.org/cf/-/cf-${finalAttrs.version}.tgz";
    hash = "sha256-T860Xp5obMVNpQtyvrqlZ6zpfZqzuwZQNGxwcCvSoAs=";
  };

  # engines: ^22.23 || ^24.22 || ^26.12; the Darwin branch's nodejs_24 is
  # still 24.21.
  nodejs = pkgs.nodejs_22;
  npmDepsHash = "sha256-qNJe5xY+/CY2pd7aNAX88pedgjnezoOgXvoeKo9bQnM=";

  # Nix owns this copy, so the daily update notice, which tells the user to
  # `npm install --global cf@latest`, would only install a second one. The
  # check runs only in a terminal and has no switch; stubbing its module
  # turns it off. The module's file name changes with every release.
  postPatch = npm.postPatch + ''

    updateCheck=$(grep -l 'as maybeStartBackgroundUpdateCheck' dist/update-check-*.mjs)
    [ "$(printf '%s\n' "$updateCheck" | wc -l)" -eq 1 ]
    cat > "$updateCheck" <<'EOF'
    export function getUpdateNotice() {}
    export function maybeStartBackgroundUpdateCheck() {}
    EOF
  '';

  inherit (npm) dontNpmBuild;

  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeWrapper
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux pkgs.autoPatchelfHook;

  # `cf dev` runs workerd, whose prebuilt binary expects an FHS loader. Only
  # workerd is patched: sharp's prebuilt addon reaches its bundled libvips
  # through $ORIGIN, and patchelf moves libvips-cpp's .plt and crashes it.
  dontAutoPatchelf = true;

  postInstall = ''
    mkdir -p $out/share/skills
    cp -R ${skills}/skills/cf-cli $out/share/skills/
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
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

  passthru = {
    inherit skills;
    updater = flake.lib.updater {
      kind = "npm";
      inherit lockfileFilter;
      followBranch = [ "skills" ];
    };
  };

  meta = {
    description = "Cloudflare's CLI for the Cloudflare API and Workers projects";
    homepage = "https://developers.cloudflare.com/cf/";
    changelog = "https://github.com/cloudflare/cf/releases/tag/cf%40${finalAttrs.version}";
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
