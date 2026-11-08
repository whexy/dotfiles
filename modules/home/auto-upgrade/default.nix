# Auto-upgrade of a standalone Home Manager setup (non-NixOS hosts) from the
# upstream repo, via the dotfiles-upgraded daemon running as a long-lived user
# service (packages/dotfiles-upgraded).
#
# The daemon learns of each commit that passes CI, from CI's announcements or
# by polling upstream, and then runs the same command documented for manual
# use, plus --refresh:
#   nh home switch <upstreamRef>/<sha> --refresh --no-nom -c <user>@<host> -b backup
#
# The <user>@<host> configuration name is deduced from the path of the
# home-configuration.nix that enabled this module (blueprint names the
# flake output after hosts/<host>/users/<user> but doesn't pass the host
# name into the module; the real machine hostname may differ).
#
# On headless servers the user manager stops when its user logs out, which
# takes this daemon down with it and silently strands the host on its current
# generation, so activation turns on lingering for the user. Check
# convergence in "<stateDir>/status.json".
{
  config,
  flake,
  options,
  lib,
  pkgs,
  perSystem,
  ...
}:
let
  cfg = config.dotfiles.autoUpgrade;
  relay = config.dotfiles.tailnetRelay;
  inherit (flake.lib) upstreamRef rollout;

  # Find the file that set dotfiles.autoUpgrade.enable = true and parse
  # "<user>@<host>" out of its path:
  #   hosts/<host>/users/<user>/home-configuration.nix
  enablingDef = lib.findFirst (def: (def.value or false) == true) null (
    options.dotfiles.autoUpgrade.enable.definitionsWithLocations or [ ]
  );
  pathMatch =
    if enablingDef != null then
      builtins.match ".*/hosts/([^/]+)/users/([^/]+)/home-configuration\\.nix" (toString enablingDef.file)
    else
      null;

  configuration =
    if cfg.configuration != null then
      cfg.configuration
    else if pathMatch != null then
      "${lib.elemAt pathMatch 1}@${lib.elemAt pathMatch 0}"
    else
      throw ''
        dotfiles.autoUpgrade: could not deduce the configuration name from
        the enabling file's path (expected hosts/<host>/users/<user>/home-configuration.nix).
        Set dotfiles.autoUpgrade.configuration explicitly.
      '';

  upgrader = import ../../../packages/dotfiles-upgraded/args.nix {
    inherit lib configuration cfg;
    fleet = flake.lib;
    package = perSystem.self.dotfiles-upgraded;
    mode = "home-manager";
    # Homes without a Tailscale daemon reach the relay through their tailnet
    # relay. The daemon runs no tailnet-relay-check: announcements are signed,
    # so whoever holds the port can only withhold them.
    relay = if relay.enable then relay.forwards.rollout.url else rollout.relay;
    ageSecrets = config.age.secrets;
  };
in
{
  options.dotfiles.autoUpgrade = import ../../../packages/dotfiles-upgraded/options.nix {
    inherit lib;
    subject = "home";
    relayRoute = "is on the tailnet, reached through `dotfiles.tailnetRelay` where that is enabled";

    configuration = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The homeConfigurations."<user>@<host>" output of the upstream repo
        to switch to. When null, the name is deduced from the path of the
        home-configuration.nix that enabled this module
        (hosts/<host>/users/<user>). Set explicitly only if the file does
        not follow that layout.
      '';
      example = "wenxuan@mars";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.stateHome}/dotfiles-upgraded";
      defaultText = lib.literalExpression ''"''${config.xdg.stateHome}/dotfiles-upgraded"'';
      readOnly = true;
      description = "Where the daemon keeps its state and publishes its health signal, status.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    dotfiles.tailnetRelay.forwards.rollout = lib.mkIf (cfg.notify.enable && relay.enable) {
      port = 47306;
      upstream = rollout.relay;
    };

    age.secrets = upgrader.secrets;

    # logind's polkit policy lets any user linger without authentication; a
    # host that tightens it needs `sudo loginctl enable-linger <user>` once.
    home.activation.enableLinger = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -e /var/lib/systemd/linger/${config.home.username} ]; then
        run ${lib.getExe' pkgs.systemd "loginctl"} enable-linger ${lib.escapeShellArg config.home.username} ||
          warnEcho "Could not enable lingering: the auto-upgrade daemon stops when ${config.home.username} logs out."
      fi
    '';

    systemd.user.services.dotfiles-upgraded = {
      Unit = {
        Description = "Auto-upgrade Home Manager from ${upstreamRef}";
        # sd-switch runs inside the daemon's `nh`, so restarting the daemon
        # during its own switch would kill that switch. A switch that changes
        # this unit reloads it instead, and the reload restarts the daemon
        # once that switch has finished (flake.lib.upgraderReload).
        X-SwitchMethod = "reload";
      };
      Service = {
        Type = "simple";
        # nh shells out to nix; the user manager on generic-Linux hosts does
        # not inherit the login PATH. Include the standard profile locations
        # as a fallback when no nix.package is selected for the user.
        Environment = [
          "PATH=${
            lib.makeBinPath (
              [
                pkgs.git
                pkgs.nh
              ]
              ++ lib.optional (config.nix.package != null) config.nix.package
            )
          }:${config.home.homeDirectory}/.nix-profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"

          # Caps only the rebuilds this daemon runs, wherever they build: an
          # unprivileged user's Nix hands the settings to nix-daemon over the
          # socket, while root's opens the store and builds in this unit.
          # Home Manager renders this list into the unit verbatim, so
          # the quotes and the literal two-character escape are both ours:
          # unquoted, systemd splits the value on the spaces around `=`; a
          # real newline would split the Environment= line instead.
          #
          # The empty access-tokens drops the gh token nix.conf includes
          # (dotfiles.nix.ghTokenFlakes). Everything this daemon fetches is
          # public, and a revoked token would fail those fetches with HTTP 401
          # before the activation that refreshes it could run. A private
          # input would need a token here.
          ''"NIX_CONFIG=max-jobs = ${toString cfg.maxJobs}\ncores = ${toString cfg.cores}\naccess-tokens ="''
        ];
        # On Linux the token's path holds a literal ${XDG_RUNTIME_DIR}, which
        # systemd expands, quoted or not, from the user manager's environment.
        ExecStart = lib.escapeShellArgs upgrader.argv;
        ExecReload = flake.lib.upgraderReload {
          inherit (pkgs) systemd util-linux;
          inherit (cfg) stateDir;
          user = true;
        };
        Restart = "always";
        RestartSec = 30;

        # Evaluation always runs here, and for a root home the builds do too.
        # IOWeight takes effect only where the user manager is delegated the
        # io controller. A rebuild the OOM killer takes is retried later.
        CPUWeight = 20;
        IOWeight = 20;
        OOMScoreAdjust = 500;
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
