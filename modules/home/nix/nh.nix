# nh: the default installable for `nh os|home|darwin` commands.
#
# NH_FLAKE points at the published repo, not a local checkout: an
# unqualified `nh os switch` means "routine update to what I pushed".
# Building local edits is the deliberate case and names the path
# explicitly (`nh os switch .`), which also reads as a local build at the
# call site.
{
  config,
  flake,
  lib,
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
        Flake reference used for `NH_FLAKE`, which nh falls back to when a
        command is given no installable. Applies to `nh os`, `nh home`, and
        `nh darwin` alike; nh's per-command `NH_*_FLAKE` variables take
        priority over it and are left unset here.

        A `github:` reference is served from the flake registry cache, so a
        bare `nh os switch` can lag behind the branch tip until the command
        is given `--refresh`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.nh = {
      enable = true;
      inherit (cfg) flake;
    };
  };
}
