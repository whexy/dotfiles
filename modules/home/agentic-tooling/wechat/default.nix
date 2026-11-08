{
  config,
  lib,
  pkgs,
  perSystem,
  flake,
  ...
}:
let
  relay = config.dotfiles.tailnetRelay;
  wechat = perSystem.self.wechat-cli;

  # The WeChat relay has no authentication, so a listener another user put
  # on the forward's port would read and answer the user's messages.
  viaRelay = pkgs.symlinkJoin {
    name = "wechat-cli-via-tailnet-relay";
    paths = [ wechat ];
    postBuild = ''
      rm $out/bin/wechat
      cat > $out/bin/wechat <<EOF
      #!${pkgs.runtimeShell}
      ${relay.checker} ${relay.forwards.wechat.address} || exit 1
      export WECHAT_RELAY_URL=${relay.forwards.wechat.url}
      exec ${lib.getExe wechat} "\$@"
      EOF
      chmod +x $out/bin/wechat
    '';
    meta.mainProgram = "wechat";
  };
in
{
  config = lib.mkIf config.dotfiles.agenticTooling.wechat.enable (
    lib.mkMerge [
      {
        home.packages = [ (if relay.enable then viaRelay else wechat) ];
        dotfiles.agents.skills = import ./skills.nix { inherit pkgs perSystem flake; };
      }
      (lib.mkIf relay.enable {
        dotfiles.tailnetRelay.forwards.wechat = {
          port = 47304;
          upstream = "https://${flake.lib.tailnetHost "wechat"}";
        };
      })
    ]
  );
}
