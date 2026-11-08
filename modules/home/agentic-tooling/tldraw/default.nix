# Live tldraw whiteboard rooms; agents read and draw diagrams that broadcast
# to anyone viewing the room. Unauthenticated: reachability is the only
# access control, which is why registration follows tailscale.
{
  config,
  lib,
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  cfg = config.dotfiles.agenticTooling.tldraw;
  relay = config.dotfiles.tailnetRelay;
  origin = "https://${flake.lib.tailnetHost "draw"}";
in
{
  config = lib.mkIf (config.dotfiles.agents.enable && cfg.enable) (
    lib.mkMerge [
      {
        dotfiles.agents = {
          skills = import ./skills.nix { inherit pkgs perSystem flake; };
          mcp.servers.tldraw.url = "${if relay.enable then relay.forwards.tldraw.url else origin}/mcp";
        };
      }
      (lib.mkIf relay.enable {
        dotfiles.tailnetRelay.forwards.tldraw = {
          port = 47305;
          upstream = origin;
        };
        dotfiles.agents.launcher.relayListeners = [ relay.forwards.tldraw.address ];
      })
    ]
  );
}
