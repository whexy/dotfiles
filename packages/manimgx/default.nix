{ pkgs }:

# ManimGX: Manim CE's scene API on a Rust + wgpu renderer. Typst sets text
# and math and x264 encodes the MP4 inside the engine, so it needs neither
# LaTeX nor ffmpeg.
#
# Installed from PyPI's wheels: the source build's Cargo scripts download
# x264, FFmpeg and NASM themselves.
let
  inherit (pkgs) lib python3;
  inherit (pkgs.stdenv.hostPlatform) isLinux;
  version = "0.1.1";

  wheels = {
    x86_64-linux = {
      platform = "manylinux_2_28_x86_64";
      hash = "sha256-GvvMtvXyf6jizifrLEbTZK+71VnzWuk9ELBvTy23R6c=";
    };
    aarch64-linux = {
      platform = "manylinux_2_28_aarch64";
      hash = "sha256-Juy9uvmdNapi5KNj/GRonItAODzJi24xu/rAW9t0lXw=";
    };
    aarch64-darwin = {
      platform = "macosx_11_0_arm64";
      hash = "sha256-Taf91+ciN8+MH1G+aDjRuyeW93RwL4XpRtL2Aza4e1g=";
    };
  };
  wheel =
    wheels.${pkgs.stdenv.hostPlatform.system}
      or (throw "manimgx: no wheel for ${pkgs.stdenv.hostPlatform.system}");

  # The Noto fonts text is set in, which manimgx requires at exact versions.
  fonts =
    pname: hash:
    python3.pkgs.buildPythonPackage rec {
      inherit pname;
      version = "2026.9.26.post1";
      format = "wheel";
      src = python3.pkgs.fetchPypi {
        pname = lib.replaceStrings [ "-" ] [ "_" ] pname;
        inherit version hash;
        format = "wheel";
        dist = "py3";
        python = "py3";
      };
    };

  repo = pkgs.fetchFromGitHub {
    owner = "academa-labs";
    repo = "manimgx";
    tag = "v${version}";
    sparseCheckout = [
      "skills/manimgx"
      "docs/content/user-guide"
      "examples"
    ];
    hash = "sha256-BWZHD1ZhNnr/R6DBgerqZw1XdNoRoPpdpAVUnXns0Gg=";
  };

  dzn = import ./dzn.nix { inherit pkgs; };

  # The agent skill, the user guide and the example films, read by path.
  # The checkout's top-level files are left out: its AGENTS.md is for
  # developing ManimGX, not for using it.
  docs = pkgs.runCommand "manimgx-docs-${version}" { } ''
    mkdir -p $out
    cp ${repo}/skills/manimgx/SKILL.md $out/
    cp -R ${repo}/docs/content/user-guide ${repo}/examples $out/
  '';
in
python3.pkgs.buildPythonApplication {
  pname = "manimgx";
  inherit version;
  format = "wheel";

  src = python3.pkgs.fetchPypi {
    pname = "manimgx";
    inherit version;
    inherit (wheel) platform hash;
    format = "wheel";
    dist = "cp313";
    python = "cp313";
    abi = "abi3";
  };

  nativeBuildInputs = lib.optionals isLinux [ pkgs.autoPatchelfHook ];
  buildInputs = lib.optionals isLinux [ pkgs.stdenv.cc.cc.lib ];

  dependencies = with python3.pkgs; [
    (fonts "manimgx-fonts" "sha256-5eIReCY93sPu+UFNK1KhyQrAEGLT6QZ0YPM1n4VMPhc=")
    (fonts "manimgx-fonts-cjk" "sha256-BdVYTHOHfzdCfPDKgGf1us6itZbHvnnort1jS7nytmY=")
    isosurfaces
    networkx
    numpy
    pillow
    skia-pathops
    svgelements
    typer
    typing-extensions
  ];

  # nixpkgs' typer trails the floor manimgx declares.
  pythonRelaxDeps = [ "typer" ];

  # On Linux, wgpu dlopens Vulkan's loader, which finds Mesa's drivers
  # through /run/opengl-driver. wgpu refuses the stock Dozen there, WSL's
  # only GPU driver, so the engine would draw with llvmpipe on the CPU; the
  # patched Dozen is added beside it (it loads libd3d12 from
  # /usr/lib/wsl/lib, and finds no adapter off WSL). The engine knowingly
  # runs on a non-conformant driver, so Mesa's warning about one is silenced.
  # On macOS wgpu draws through Metal and needs none of this.
  makeWrapperArgs = lib.optionals isLinux [
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    "${lib.makeLibraryPath [ pkgs.vulkan-loader ]}:/usr/lib/wsl/lib"
    "--prefix"
    "VK_ADD_DRIVER_FILES"
    ":"
    "${dzn}/share/vulkan/icd.d"
    "--set-default"
    "MESA_VK_IGNORE_CONFORMANCE_WARNING"
    "1"
  ];

  pythonImportsCheck = [ "manimgx" ];

  passthru = { inherit docs; };

  meta = {
    description = "Render Manim CE scenes to video on a Rust GPU engine";
    homepage = "https://github.com/academa-labs/manimgx";
    # MIT; the wheel bundles x264, which makes it GPL as a whole.
    license = [
      lib.licenses.mit
      lib.licenses.gpl3Plus
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "manimgx";
    platforms = lib.attrNames wheels;
  };
}
