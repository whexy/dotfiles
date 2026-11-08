# Keyboard group: remappers and input methods.
#
# Integrated homes follow the system keyboard group, which installs the
# remapper and input method these configure; the options are set directly
# only in standalone homes.
args@{ lib, ... }:
let
  osConfig = args.osConfig or null;
  fromSystem =
    name: description:
    lib.mkOption {
      type = lib.types.bool;
      default = if osConfig != null then osConfig.dotfiles.keyboard.${name}.enable else false;
      defaultText = lib.literalExpression "osConfig.dotfiles.keyboard.${name}.enable, or false without osConfig";
      description = "Whether to enable ${description}.";
    };
in
{
  options.dotfiles.keyboard = {
    karabiner.enable = fromSystem "karabiner" "Karabiner-Elements (macOS)";
    fcitx5.enable = fromSystem "fcitx5" "fcitx5 input method with rime (Linux)";
  };

  imports = [
    ./karabiner.nix
    ./fcitx5.nix
  ];
}
