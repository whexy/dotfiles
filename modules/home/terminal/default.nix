# Terminal group: emulators and multiplexers.
args@{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.dotfiles.terminal;
  osConfig = args.osConfig or null;

  # Rex's login server on NixOS, or Tailscale Serve to the Rex app on macOS,
  # each for the host's primary user only.
  systemRoute =
    let
      inherit (osConfig.dotfiles) host network;
      account = "${host.username}@${flake.lib.tailnetHost host.hostName}";
    in
    if
      network.tailscale.enable
      && network.tailscale.rex.enable
      && !host.wsl
      && config.home.username == host.username
    then
      # Rex clients try HTTPS on 7297 for a bare host name.
      if network.tailscale.rex.port == 7297 then
        account
      else
        "https://${account}:${toString network.tailscale.rex.port}"
    else
      null;
in
{
  options.dotfiles.terminal = {
    ghostty = {
      enable = lib.mkEnableOption "the Ghostty terminal emulator";
      package = lib.mkOption {
        type = lib.types.package;
        # nixpkgs builds Ghostty from source only for Linux; on macOS it
        # repackages the upstream app.
        default = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.ghostty-bin else pkgs.ghostty;
        defaultText = lib.literalExpression "if isDarwin then pkgs.ghostty-bin else pkgs.ghostty";
        description = "Ghostty package, whose terminfo and shell integration other modules use too.";
      };
      terminfo.enable = lib.mkEnableOption "Ghostty's xterm-ghostty terminfo entry, for Ghostty terminals that reach this machine";
    };
    tmux.enable = lib.mkEnableOption "tmux";
    zellij.enable = lib.mkEnableOption "zellij";
    rex = {
      enable = lib.mkEnableOption "the Rex Beta terminal multiplexer app with Ghostty's look (macOS)";
      terminfo.enable = lib.mkEnableOption "Rex's xterm-rex terminfo entry, for Rex terminals that reach this machine";
      server = {
        enable = lib.mkEnableOption ''
          Rex's personal server as a user service, so sessions outlive their
          clients, with `rex` on the profile (Linux)
        '';
        hostName = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "venus-rex";
          description = ''
            Name of the server's own node on the tailnet, or null for none. The
            node joins with the tailnet relay's OAuth client and tags (homes
            that run dotfiles.tailnetRelay), and every caller the tailnet
            policy lets reach it on 443 gets a shell as this user.
          '';
        };
      };
      local = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        default =
          if pkgs.stdenv.hostPlatform.isDarwin then
            cfg.rex.enable
          else
            osConfig.services.rex.loginServer.enable or false || cfg.rex.server.enable;
        defaultText = lib.literalExpression "the Rex app, Rex's login server, or dotfiles.terminal.rex.server";
        description = ''
          Whether this machine runs a Rex server for this user and puts `rex`
          on the profile: the Rex app on macOS, Rex's login server on NixOS,
          or the personal server.
        '';
      };
      route = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default =
          if osConfig != null then
            systemRoute
          else if cfg.rex.server.enable && cfg.rex.server.hostName != null then
            "https://${flake.lib.tailnetHost cfg.rex.server.hostName}"
          else
            null;
        defaultText = lib.literalExpression "the host's Rex route on the tailnet, if any";
        example = "ssh://root@proxmox.at-basking.ts.net";
        description = ''
          Address the Macs' Rex app reaches this user's Rex server at, in a
          form `rex -S` accepts, or null when they cannot. Every Mac with the
          Rex app declares each flake home's route as a host labelled with
          the home's host name. Standalone homes reached over SSH set it
          themselves.
        '';
      };
    };
    adopt.enable = lib.mkEnableOption "totmux/tozellij job adoption wrappers (Linux)";
  };

  imports = [
    ./adopt.nix
    ./ghostty.nix
    ./rex.nix
    ./tmux.nix
    ./zellij.nix
  ];

  config = lib.mkIf cfg.ghostty.terminfo.enable {
    home.packages = [ cfg.ghostty.package.terminfo ];
  };
}
