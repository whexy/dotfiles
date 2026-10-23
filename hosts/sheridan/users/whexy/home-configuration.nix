{ inputs, ... }:
{
  imports = [ inputs.self.homeModules.host-user ];

  dotfiles = {
    wm.darwin.windowManager = "aerospace";
    agents.spark = {
      enable = true;
      server = {
        enable = true;
        accessAud = "7a04718989615786c081ddb39372041a47193395d007db76ac6d42867e05346c";
      };
    };
  };
}
