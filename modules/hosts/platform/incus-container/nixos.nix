{
  config,
  options,
  lib,
  ...
}:
let
  cfg = config.dotfiles.platform.incusContainer;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = config.boot.isContainer;
            message = "dotfiles.platform.incusContainer needs the nixpkgs LXC profile; set incusContainer = true in flake.lib.nixosHost.";
          }
        ];

        # The LXC profile pulls in profiles/minimal.nix, which targets
        # throwaway containers. This is a persistent dev host, so restore the
        # regular NixOS defaults it turns off.
        documentation = {
          man.enable = true;
          doc.enable = true;
          info.enable = true;
        };
        environment.defaultPackages = options.environment.defaultPackages.default;

        # The profile opens a passwordless root console login. This host is
        # reached as dotfiles.host.username like every other NixOS host.
        users.users.root.initialHashedPassword = lib.mkOverride 149 null;
        services.getty.helpLine = lib.mkForce "";

        # The container's veth is up before init runs, so NetworkManager
        # assumes it as externally configured and never runs DHCP; it also
        # drags in wpa_supplicant with no Wi-Fi to manage. The LXC profile
        # already configures DHCP for the veth.
        dotfiles.network.networkmanager.enable = lib.mkForce false;

        # binfmt_misc registration needs the hypervisor kernel to hand the
        # container its own binfmt_misc mount; without it nix would advertise
        # extra-platforms it cannot run.
        dotfiles.compat.binfmt.enable = lib.mkForce false;
      }

      # Installer leftovers of the LXC profile: a bundled nixpkgs channel and a
      # generated /etc/nixos/configuration.nix, both meaningless for a flake
      # host. Their options exist only where that profile is imported.
      (lib.optionalAttrs (options.system ? installer) { system.installer.channel.enable = false; })
      (lib.optionalAttrs (options ? installer) { installer.cloneConfig = false; })
    ]
  );
}
