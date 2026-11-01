{ pkgs, flake }:

pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "perfect-dos-vga-437-nerd-font";
  version = "0-unstable-2018-09-18";

  src = pkgs.fetchFromGitHub {
    owner = "CP437";
    repo = "PerfectDOSVGA437";
    rev = "b3ed9409bc970ad9c645bfc242264746c9deb43a";
    hash = "sha256-vhp790fgXiZp4pwWBZBTNabke0DOtM/bUHM/Q+y65ps=";
  };

  nativeBuildInputs = [
    pkgs.fontforge
    pkgs.nerd-font-patcher
  ];

  buildPhase = ''
    runHook preBuild
    nerd-font-patcher PerfectDOSVGA437Win.ttf \
      --complete \
      --mono \
      --name "Perfect DOS VGA 437 Nerd Font" \
      --outputdir . \
      --no-progressbars
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 PerfectDOSVGA437NerdFont-Regular.ttf \
      $out/share/fonts/truetype/PerfectDOSVGA437NerdFont-Regular.ttf
    runHook postInstall
  '';

  # The repository has no releases; follow its default branch.
  passthru.updater = flake.lib.updater {
    kind = "nix-update";
    args = [ "--version=branch" ];
  };

  meta = {
    description = "Perfect DOS VGA 437 Win patched with Nerd Fonts glyphs";
    homepage = "https://github.com/CP437/PerfectDOSVGA437";
    changelog = "https://github.com/CP437/PerfectDOSVGA437/commits/${finalAttrs.src.rev}";
    license = pkgs.lib.licenses.free;
    platforms = pkgs.lib.platforms.all;
  };
})
