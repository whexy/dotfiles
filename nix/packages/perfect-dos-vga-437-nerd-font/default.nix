{ pkgs }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "perfect-dos-vga-437-nerd-font";
  version = "2025-04-16";

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

  meta = {
    description = "Perfect DOS VGA 437 Win patched with Nerd Fonts glyphs";
    homepage = "https://github.com/CP437/PerfectDOSVGA437";
    license = pkgs.lib.licenses.free;
    platforms = pkgs.lib.platforms.all;
  };
}
