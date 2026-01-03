# AI coding agents configuration
{ pkgs, ... }:
let
  opencode-wrapped = pkgs.mkOpWrapped pkgs.unstable.opencode
    [ "opencode" ]
    {
      "ANTHROPIC_API_KEY" = "op://Developer/Anthropic API/credential";
      "OPENAI_API_KEY" = "op://Developer/OpenAI API/credential";
    };
in
{
  home.packages = [ opencode-wrapped ];
}
