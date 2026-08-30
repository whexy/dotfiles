# AI quota pills for the status bar.
#
# Each selected bar fetches the public quota API and renders current data directly.
# API metadata is shared in ./shared.nix; quota semantics live in ./summary.jq.
{
  imports = [
    ./sketchybar.nix
    ./waybar.nix
    ./eww.nix
  ];
}
