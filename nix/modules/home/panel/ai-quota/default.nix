# AI proxy quota pills for the status bar.
#
# Contributes kimi/codex pills to sketchybar (macOS) and waybar (Linux)
# whenever the agents module provisions proxy accounts. All summarization
# logic lives in ./summary.jq; these files only wire bar-specific plumbing
# and poll a shared JSON cache refreshed by ai-quota --json.
{
  imports = [
    ./sketchybar.nix
    ./waybar.nix
  ];
}
