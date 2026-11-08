# The daemon's command line, from its options (options.nix), and the agenix
# secrets it reads. A plain function shared by the NixOS, Darwin and home
# modules.
{
  lib,
  # flake.lib, for the values of fleet.nix.
  fleet,
  package,
  mode,
  # The module's dotfiles-upgraded options.
  cfg,
  # The flake output to switch to.
  configuration ? cfg.configuration,
  # Origin of the announcement relay as this machine reaches it.
  relay ? fleet.rollout.relay,
  # The module's config.age.secrets, read only when it reports failures.
  ageSecrets,
  # Flags that follow --mode.
  modeFlags ? [ ],
}:
{
  secrets = lib.optionalAttrs cfg.reportFailures {
    upgrade-webhook-token.file = ../../secrets/upgrade-webhook-token.age;
  };

  argv = [
    (lib.getExe package)
    "--mode=${mode}"
  ]
  ++ modeFlags
  ++ [
    "--configuration=${configuration}"
    "--flake=${fleet.upstreamRef}"
    "--state-dir=${cfg.stateDir}"
    "--poll-interval=${cfg.pollInterval}"
    "--max-attempts=${toString cfg.maxAttempts}"
    "--require-ci-pass=${lib.boolToString cfg.requireCiPass}"
  ]
  ++ lib.optionals cfg.notify.enable [
    "--notify-url=${relay}/${fleet.rollout.topic}"
    "--notify-public-key=${fleet.rollout.publicKey}"
    "--notified-poll-interval=${cfg.notify.pollInterval}"
  ]
  ++ lib.optionals cfg.reportFailures [
    "--failure-webhook=${fleet.upgradeFailureWebhook}"
    "--failure-webhook-token-file=${ageSecrets.upgrade-webhook-token.path}"
  ];
}
