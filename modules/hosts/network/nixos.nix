{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.network;
  # Tailscale requires util-linux's su -w; NixOS's Shadow su lacks it.
  # Keep this root-invoked helper unprivileged and its PAM policy separate
  # from the system-wide su service.
  tailscaleSu = pkgs.util-linux.overrideAttrs (old: {
    configureFlags = lib.remove "--disable-su" old.configureFlags ++ [ "--enable-su" ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace login-utils/su-common.c \
        --replace-fail '#define PAM_SRVNAME_SU "su"' '#define PAM_SRVNAME_SU "tailscale-ssh"' \
        --replace-fail '#define PAM_SRVNAME_SU_L "su-l"' '#define PAM_SRVNAME_SU_L "tailscale-ssh"'
    '';
  });
  tailscaleSuPath = pkgs.runCommand "tailscale-ssh-su" { } ''
    mkdir -p "$out/bin"
    ln -s ${lib.getBin tailscaleSu}/bin/su "$out/bin/su"
  '';
  # Match the PAM PATH that Tailscale normally reads, retaining its per-user
  # placeholders. Fail evaluation if NixOS changes that file's format.
  pamPathMatches = lib.filter (match: match != null) (
    map (line: builtins.match ''PATH[ \t]+DEFAULT="([^"]*)"'' line) (
      lib.splitString "\n" config.environment.etc."pam/environment".text
    )
  );
  pamPath =
    assert lib.assertMsg (builtins.length pamPathMatches == 1) "Expected one PATH in pam/environment";
    builtins.head (builtins.head pamPathMatches);
in
{
  config = lib.mkMerge [
    {
      networking = {
        firewall.enable = cfg.firewall.enable;
        nftables.enable = cfg.nftables.enable;
      };
    }

    (lib.mkIf cfg.networkmanager.enable { networking.networkmanager.enable = true; })

    (lib.mkIf cfg.tailscale.enable {
      security.pam.services.tailscale-ssh = {
        rootOK = true;
        startSession = true;
      };
      # The daemon's PATH does not control SSH children; this override does.
      # Expose only su so other util-linux commands retain their normal lookup.
      systemd.services.tailscaled.environment.TAILSCALE_SSH_DEFAULT_PATH =
        "${tailscaleSuPath}/bin:${pamPath}";
      services.tailscale = {
        enable = true;
        port = cfg.tailscale.port;
        # trustedInterfaces below covers traffic inside the tunnel, not the UDP
        # underlay tailscaled binds. Without this the nixos-fw input chain drops
        # unsolicited packets on that port, so a peer whose source port this
        # host cannot predict -- a Kubernetes pod behind flannel's `MASQUERADE
        # --random-fully` -- never establishes a direct path and stays on DERP.
        # Ordinary peers hide the problem because this host dials them first and
        # conntrack admits the reply.
        openFirewall = true;
      };
      networking.firewall.trustedInterfaces = [ "tailscale0" ];
    })
  ];
}
