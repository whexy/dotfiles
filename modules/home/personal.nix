{
  imports = [
    ./dev.nix
    ./personal/ghostty.nix
  ];

  home-manager.users.whexy =
    { config, pkgs, ... }:
    {
      home.packages = with pkgs; [
        # TODO: some GUI apps
      ];
    };
}
