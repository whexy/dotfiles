{ pkgs, flake, ... }:

# asc, the App Store Connect CLI. nixpkgs packages it as `asccli`, five
# major versions behind upstream; `pkgs.asc` is an unrelated game.
let
  inherit (pkgs) lib stdenv;
in
pkgs.buildGo127Module (finalAttrs: {
  pname = "asc";
  version = "6.3.0";

  src = pkgs.fetchFromGitHub {
    owner = "rorkai";
    repo = "App-Store-Connect-CLI";
    tag = finalAttrs.version;
    hash = "sha256-iT2d8PEmxMyE/XDIFXUWfTaMCuXJl6gLSUwzjg1ARGI=";
  };

  vendorHash = "sha256-TgZJSRRleDJmqz9YwIvoslh+9fmytJkl83oF4PNihwE=";

  subPackages = [ "." ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
  ];

  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeBinaryWrapper
  ];

  postInstall = ''
    mv $out/bin/App-Store-Connect-CLI $out/bin/asc
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd asc \
      --bash <(HOME=$TMPDIR ASC_TELEMETRY_DISABLED=1 $out/bin/asc completion --shell bash) \
      --fish <(HOME=$TMPDIR ASC_TELEMETRY_DISABLED=1 $out/bin/asc completion --shell fish) \
      --zsh <(HOME=$TMPDIR ASC_TELEMETRY_DISABLED=1 $out/bin/asc completion --shell zsh)
  ''
  # Upstream sends usage telemetry unless told not to; `asc telemetry
  # disable` would persist that only per machine. Setting the variable
  # yourself overrides this default.
  + ''
    wrapProgram $out/bin/asc --set-default ASC_TELEMETRY_DISABLED 1
  '';

  # The root package's tests exercise upstream's release scripts, and dozens
  # of the CLI's own tests assume a developer machine (file modes, /var/tmp,
  # web session caches), so they fail in the sandbox. The install check
  # still runs the built binary.
  doCheck = false;

  nativeInstallCheckInputs = [ pkgs.versionCheckHook ];
  versionCheckProgramArg = "version";
  doInstallCheck = true;

  passthru.updater = flake.lib.updater { kind = "nix-update"; };

  meta = {
    description = "Scriptable CLI for the App Store Connect API";
    homepage = "https://asccli.sh";
    changelog = "https://github.com/rorkai/App-Store-Connect-CLI/releases/tag/${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "asc";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
