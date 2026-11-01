{ pkgs, flake }:

# ManimGX: Manim CE's scene API on a Rust + wgpu renderer. Typst sets text
# and math and x264 encodes the MP4 inside the engine, so it needs neither
# LaTeX nor ffmpeg.
#
# Installed from PyPI's wheels: the source build's Cargo scripts download
# x264, FFmpeg and NASM themselves.
let
  inherit (pkgs) lib python3;
  inherit (pkgs.stdenv.hostPlatform) isLinux system;
  sources = lib.importJSON ./sources.json;
  inherit (sources) version;

  wheelPlatforms = {
    x86_64-linux = "manylinux_2_28_x86_64";
    aarch64-linux = "manylinux_2_28_aarch64";
    aarch64-darwin = "macosx_11_0_arm64";
  };

  # The Noto fonts text is set in, which manimgx requires at exact versions.
  fonts =
    pname:
    python3.pkgs.buildPythonPackage rec {
      inherit pname;
      inherit (sources.fonts.${pname}) version;
      format = "wheel";
      src = python3.pkgs.fetchPypi {
        pname = lib.replaceStrings [ "-" ] [ "_" ] pname;
        inherit version;
        inherit (sources.fonts.${pname}) hash;
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
    inherit (sources.repo) hash;
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
    platform = wheelPlatforms.${system} or (throw "manimgx: no wheel for ${system}");
    hash = sources.hashes.${system};
    format = "wheel";
    dist = "cp313";
    python = "cp313";
    abi = "abi3";
  };

  nativeBuildInputs = lib.optionals isLinux [ pkgs.autoPatchelfHook ];
  buildInputs = lib.optionals isLinux [ pkgs.stdenv.cc.cc.lib ];

  dependencies = with python3.pkgs; [
    (fonts "manimgx-fonts")
    (fonts "manimgx-fonts-cjk")
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

  passthru = {
    inherit docs repo;
    # update.py pins the wheels and fonts from PyPI's digests.
    updater = flake.lib.updater {
      kind = "script";
      settings.platforms = wheelPlatforms;
      subpackages = [ "repo" ];
    };
  };

  meta = {
    description = "Render Manim CE scenes to video on a Rust GPU engine";
    homepage = "https://github.com/academa-labs/manimgx";
    changelog = "https://github.com/academa-labs/manimgx/releases/tag/v${version}";
    # MIT; the wheel bundles x264, which makes it GPL as a whole.
    license = [
      lib.licenses.mit
      lib.licenses.gpl3Plus
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "manimgx";
    platforms = lib.attrNames sources.hashes;
  };
}
