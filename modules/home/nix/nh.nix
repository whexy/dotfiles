# nh: the default installable for `nh os|home|darwin` commands.
#
# NH_FLAKE points at the published repo, not a local checkout: an
# unqualified `nh os switch` means "routine update to what I pushed".
# Building local edits is the deliberate case and names the path
# explicitly (`nh os switch .`), which also reads as a local build at the
# call site.
#
# The default is baked into the nh wrapper rather than exported as a session
# variable: Home Manager's session variables reach only the shells it
# configures, never a distro login shell such as root's bash on a standalone
# host, and are skipped under a tmux server started before activation.
{
  config,
  flake,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.nix.nh;
in
{
  options.dotfiles.nix.nh = {
    enable = lib.mkEnableOption "nh, a Nix CLI helper";

    flake = lib.mkOption {
      type = lib.types.str;
      default = flake.lib.upstreamRef;
      example = "/home/wenxuan/Personal/dotfiles";
      description = ''
        Flake reference nh falls back to when a command is given no
        installable, set as the `NH_FLAKE` default in its wrapper. Applies to
        `nh os`, `nh home`, and `nh darwin` alike; `NH_FLAKE` or nh's
        per-command `NH_*_FLAKE` variables in the environment take priority.

        A `github:` reference is served from the flake registry cache, so a
        bare `nh os switch` can lag behind the branch tip until the command
        is given `--refresh`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.nh = {
      enable = true;
      package = pkgs.symlinkJoin {
        inherit (pkgs.nh) name meta;
        paths = [ pkgs.nh ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/nh --set-default NH_FLAKE ${lib.escapeShellArg cfg.flake}
        '';
      };
    };
  };
}
