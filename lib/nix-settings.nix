# Shared client settings; daemon trust determines whether cache overrides apply.
{
  extra-substituters = [
    "https://cache.numtide.com"
    "https://nix-community.cachix.org"
    "https://niri.cachix.org"
    "https://vicinae.cachix.org"
    "https://whexy.cachix.org"
  ];
  extra-trusted-public-keys = [
    "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    "whexy.cachix.org-1:XzmCWs+qh3vMtB4p1joLM+ajn5z/UYgZOyxykzEDV2o="
  ];
  experimental-features = [
    "nix-command"
    "flakes"
  ];
  accept-flake-config = true;
  warn-dirty = false;

  # Never serve an unlocked ref like `github:whexy/x` from the fetcher
  # cache: anything worth fetching unlocked is worth fetching fresh.
  # Locked flake inputs are content-addressed and unaffected.
  tarball-ttl = 0;
}
