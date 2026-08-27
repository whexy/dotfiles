# AI quota pills for the status bar.
#
# Each selected bar owns its fetch interval and renders current data directly.
# Provider selection and quota semantics live in ./summary.jq.
{
  imports = [
    ./sketchybar.nix
    ./waybar.nix
    ./eww.nix
  ];
}
