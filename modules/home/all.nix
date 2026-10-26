# Aggregates every dotfiles home feature module (options + config in each
# <feature>/default.nix). Capability presets (caps/<cap>.nix) are NOT
# imported here — they are imported selectively via flake.lib.homeCapsModules.
{
  inputs,
  flake,
  config,
  ...
}:
{
  imports = [
    inputs.agenix.homeManagerModules.default
    inputs.nix-index-database.homeModules.default
  ]
  ++ flake.lib.importDir ./. {
    pattern = "default.nix";
    exclude = [ "caps/" ];
  };

  # A user cannot read the host key, so it decrypts with a key generated on
  # that machine for agenix alone. agenix's default, ~/.ssh/id_ed25519, may
  # be a personal login key.
  age.identityPaths = [
    (
      if config.home.username == "root" then
        "/etc/ssh/ssh_host_ed25519_key"
      else
        "${config.home.homeDirectory}/.ssh/agenix_ed25519"
    )
  ];
}
