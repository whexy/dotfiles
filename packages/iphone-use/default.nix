{ pkgs, flake }:
let
  inherit (pkgs) lib;
in
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "iphone-use";
  version = "0.3.16";

  # Its setup pins the WebDriverAgent revision it fetches into the user's
  # state directory, so the checkout stays a runtime concern.
  src = pkgs.fetchFromGitHub {
    owner = "zhongerxin";
    repo = "iPhone-use";
    tag = "v${finalAttrs.version}";
    hash = "sha256-1+63KhNJEx9UDlazNqV25k7z1hMECeEMqDOEjRbHQsE=";
  };

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/iphone-use/tooling
    cp -r assets server skills $out/share/iphone-use/
    # The server reads its skills beside it; agents read a copy.
    mkdir -p $out/share/skills
    cp -R skills/*/ $out/share/skills/
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

  passthru.updater = flake.lib.updater { kind = "nix-update"; };

  meta = {
    description = "Drive an iPhone through WebDriverAgent";
    homepage = "https://github.com/zhongerxin/iPhone-use";
    changelog = "https://github.com/zhongerxin/iPhone-use/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    # Its setup tools need Xcode, but its phone tools need only a reachable
    # WebDriverAgent, which iphone-use-select provides on Linux too.
    platforms = lib.platforms.unix;
    mainProgram = "iphone-use-mcp";
  };
})
