# whexy/ci-cache's Nix cache of Woodpecker CI builds, served only on the
# tailnet. connect-timeout and fallback apply to every substituter.
{
  # Behind cache.nixos.org (40) and the cachix caches (41), so Nix asks it
  # only for paths none of them have, such as builds of whexy/* repositories.
  extra-substituters = [ "https://ci-cache.at-basking.ts.net/nix?priority=50" ];
  extra-trusted-public-keys = [
    "ci-cache.clusters.work-1:YmSEbVm4BQqDT9CsLHgTypezIGiR5lqf6OlzBB4Ftiw="
  ];

  # Off the tailnet a request here fails after five tries: about 5 s when the
  # host name does not resolve, five connect timeouts when the address is
  # unreachable (30 s at 5 s, 80 s at the default 15 s). A Nix command pays
  # this when it first asks this cache for a path, or when it opens the cache
  # without its nix-cache-info cached (Nix keeps it 7 days).
  connect-timeout = 5;

  # While nix-cache-info is cached, that failed lookup aborts the build
  # unless Nix may fall back to building the path. Fallback also stops Nix
  # asking this cache for 60 s after a failure.
  fallback = true;
}
