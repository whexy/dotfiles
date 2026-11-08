# SketchyBar's Liquid Glass look, shared by the bar and the items feature
# modules add to it.
{ config }:
let
  # macOS Liquid Glass palette (0xAARRGGBB): dark-variant system colors for
  # state, translucent white tints for the glass capsules. Status icons stay
  # monochrome white; color is reserved for state (charging, low, muted) and
  # the accent-blue active workspace.
  colors = {
    bar = "0x00000000"; # fully transparent, wallpaper shows through
    fg = "0xffffffff"; # primary text/icons
    fgDim = "0xb3ffffff"; # 70% white, empty workspaces and the front app
    glass = "0x1affffff"; # 10% white, default item capsule
    glassBorder = "0x40ffffff"; # 25% white hairline, capsule edge highlight
    track = "0x26ffffff"; # 15% white, unfilled slider track
    red = "0xffff453a"; # systemRed: muted, critical
    yellow = "0xffffd60a"; # systemYellow: battery low, quota warning
    green = "0xff30d158"; # systemGreen: charging, live SSH context
    greenGlass = "0x2630d158"; # 15% systemGreen, SSH pill background
    greenBorder = "0x8030d158"; # 50% systemGreen, SSH pill border
    blue = "0xff0a84ff"; # systemBlue, active workspace pill
    gray = "0xff98989d"; # systemGray, stale or fetch error
    purple = "0xffbf5af2"; # systemPurple, neutral reading
  };

  # The capsule every item draws by default; brackets reuse it to draw one
  # capsule behind a group of items.
  capsule = {
    color = colors.glass;
    height = 26;
    corner_radius = 13;
    border_width = 1;
    border_color = colors.glassBorder;
  };
in
{
  inherit colors capsule;

  capsuleSettings = {
    "background.drawing" = "on";
    "background.color" = capsule.color;
    "background.height" = capsule.height;
    "background.corner_radius" = capsule.corner_radius;
    "background.border_width" = capsule.border_width;
    "background.border_color" = capsule.border_color;
  };

  mkAgent = name: programArguments: {
    enable = true;
    config = {
      ProgramArguments = programArguments;
      ProcessType = "Interactive";
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/${name}.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/${name}.err.log";
    };
  };
}
