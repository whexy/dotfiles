# AI coding agents configuration
{ pkgs, ... }:
let
  # Use daily-built opencode from llm-agents.nix
  opencode-wrapped = pkgs.mkOpWrapped pkgs.llm-agents.opencode [ "opencode" ] {
    "ANTHROPIC_API_KEY" = "op://Developer/Anthropic API/credential";
    "OPENAI_API_KEY" = "op://Developer/OpenAI API/credential";
  };
in
{
  home.packages = [ opencode-wrapped ];
}
