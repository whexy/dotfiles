# Panel group: status bar (Waybar or Eww on Linux, SketchyBar on macOS)
# and their pills.
#
# Feature modules contribute pills through the renderers' extension points
# declared here (eww.*, sketchybar.*) or, for Waybar, by merging into
# programs.waybar with mkOrder, so the renderers stay feature-agnostic.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.panel;

  sketchybarItem = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      kind = lib.mkOption {
        type = lib.types.enum [
          "item"
          "slider"
        ];
        default = "item";
      };
      width = lib.mkOption {
        type = lib.types.ints.positive;
        default = 40;
      };
      side = lib.mkOption {
        # "left", "right", or "popup.<item>" to nest inside an item's popup.
        type = lib.types.strMatching "left|right|popup\\..+";
      };
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
      clickScript = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      subscribe = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };

  # A bracket draws one shared background behind a set of member items, e.g.
  # the wm module's workspace capsule.
  sketchybarBracket = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      members = lib.mkOption { type = lib.types.listOf lib.types.str; };
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
    };
  };
in
{
  options.dotfiles.panel = {
    waybar.enable = lib.mkEnableOption "the Linux status bar";
    linuxBar = lib.mkOption {
      type = lib.types.enum [
        "waybar"
        "eww"
      ];
      default = "waybar";
      description = "Which renderer renders the Linux status bar.";
    };
    sketchybar.enable = lib.mkEnableOption "SketchyBar status bar (macOS)";

    renderer = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "waybar"
          "eww"
          "sketchybar"
        ]
      );
      readOnly = true;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin then
          if cfg.sketchybar.enable then "sketchybar" else null
        else if cfg.waybar.enable then
          cfg.linuxBar
        else
          null;
      defaultText = lib.literalMD "the bar the options above select on this platform";
      description = "The bar this home renders, or null; every renderer and pill gates on it.";
    };

    renpho.enable = lib.mkEnableOption "Renpho smart-scale panel pill";
    aiQuota.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.dotfiles.agents.enable;
      defaultText = lib.literalExpression "config.dotfiles.agents.enable";
      description = "Whether to show AI quota pills in the bar and the tmux status line.";
    };
    aiQuota.showCountdown = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to show the reset countdown in AI quota bar pills.";
    };

    eww = {
      defs = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra yuck definitions (defpoll/defvar/defwidget) merged into eww.yuck.";
      };

      styles = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra SCSS appended to eww.scss after the base styles, so the Material You palette variables stay in scope.";
      };

      left = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Widget names shown on the bar's left slot.";
      };

      center = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Widget names shown on the bar's center slot.";
      };

      right = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Widget names shown on the bar's right slot.";
      };
    };

    sketchybar = {
      items = lib.mkOption {
        type = lib.types.listOf sketchybarItem;
        default = [ ];
        description = ''
          Extra bar items rendered after the built-in ones, letting feature
          modules contribute items without touching the sketchybar renderer.
        '';
      };

      events = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Custom sketchybar events to register before items are added. Each
          event is triggered once at the end of the config so subscribers
          render their initial state.
        '';
      };

      brackets = lib.mkOption {
        type = lib.types.listOf sketchybarBracket;
        default = [ ];
        description = ''
          Brackets rendered after all items, letting feature modules draw one
          shared background behind a group of items they contributed.
        '';
      };
    };
  };

  # homeModules.all also imports these by file path. The module system keys
  # imports by path string, and ./renpho is not ./renpho/default.nix, so a
  # directory import would load each module twice.
  imports = [
    ./waybar.nix
    ./eww.nix
    ./sketchybar.nix
    ./renpho/default.nix
    ./wm/default.nix
    ./ai-quota/default.nix
  ];
}
