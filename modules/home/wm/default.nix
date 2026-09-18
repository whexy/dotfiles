# WM group: window managers (niri on Linux, AeroSpace or Paneru on macOS).
args@{
  config,
  inputs,
  lib,
  ...
}:
let
  osConfig = args.osConfig or null;
  isDarwin = osConfig != null && lib.hasSuffix "-darwin" osConfig.dotfiles.host.system;
in
{
  options.dotfiles.wm = {
    niri.enable = lib.mkEnableOption "the niri Wayland compositor";
    darwin = {
      enable = lib.mkEnableOption "window management on macOS";
      windowManager = lib.mkOption {
        type = lib.types.enum [
          "aerospace"
          "paneru"
        ];
        default = "aerospace";
        description = "Window manager to use on macOS. Paneru is experimental.";
      };
    };
  };

  imports = [
    inputs.niri.homeModules.niri
    ./niri.nix
    ./aerospace.nix
  ]
  ++ lib.optionals isDarwin [
    inputs.paneru.homeModules.paneru
    ./paneru.nix
  ];

  config = {
    assertions = [
      {
        assertion = !config.dotfiles.wm.darwin.enable || isDarwin;
        message = "dotfiles.wm.darwin can only be enabled on macOS.";
      }
    ];
  };
}
