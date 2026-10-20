{ pkgs }:
let
  inherit (pkgs) lib;
in
pkgs.stdenv.mkDerivation {
  pname = "iphone-use";
  version = "0.3.15";

  # Release 0.3.15. Its setup pins the WebDriverAgent revision it fetches into
  # the user's state directory, so the checkout stays a runtime concern.
  src = pkgs.fetchFromGitHub {
    owner = "zhongerxin";
    repo = "iPhone-use";
    rev = "80006885df81531ce7a874b3b0df65980e25e59b";
    hash = "sha256-JwoDQ053h18A5NrOzrlvJiID7w/G+L4HMZ1hIOxbvf8=";
  };

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/iphone-use/tooling
    cp -r assets server skills $out/share/iphone-use/
    install -m644 plugin.json $out/share/iphone-use/plugin.json

    # The setup worker copies these four files into its state directory and
    # runs `npm ci` there, so node_modules must not come from the store.
    for file in package.json package-lock.json forward.mjs screen-stream.mjs; do
      install -m644 tooling/$file $out/share/iphone-use/tooling/$file
    done

    # The server shells out to Xcode, Node and git; keep the system paths so
    # xcrun and xcodebuild resolve through xcode-select. Analytics stays off
    # unless a user opts in.
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/iphone-use-mcp \
      --add-flags ${placeholder "out"}/share/iphone-use/server/iphone_use.py \
      --prefix PATH : ${
        lib.makeBinPath [
          pkgs.python3
          pkgs.nodejs_24
          pkgs.git
        ]
      }:/usr/bin:/bin:/usr/sbin:/sbin \
      --set IPHONE_USE_ANALYTICS 0

    runHook postInstall
  '';

  meta = {
    description = "Drive a USB-connected iPhone through a local WebDriverAgent";
    homepage = "https://github.com/zhongerxin/iPhone-use";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
    mainProgram = "iphone-use-mcp";
  };
}
