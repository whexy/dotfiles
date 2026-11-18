# The hosts a Mac's Rex app declares: every flake home's
# dotfiles.terminal.rex.route but the Mac's own, labelled with the home's
# host name. Rex leaves out a declared host whose label a stored one already
# uses, so hosts added in the app keep their place.
{
  lib,
  flake,
  # Host name of the Mac, whose own home is never evaluated.
  self,
}:
let
  hostNames = lib.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../../../hosts)
  );
  systems = flake.nixosConfigurations // flake.darwinConfigurations;
  # CI evaluates standalone homes for x86_64-linux; the route is the same
  # for every system.
  standalone = flake.legacyPackages.x86_64-linux.homeConfigurations;

  homesOf =
    host:
    if systems ? ${host} then
      map (home: {
        inherit home;
        system = systems.${host}.config;
      }) (lib.attrValues systems.${host}.config.home-manager.users)
    else
      map (name: {
        home = standalone.${name}.config;
        system = null;
      }) (lib.filter (name: lib.last (lib.splitString "@" name) == host) (lib.attrNames standalone));

  icon =
    system:
    if system == null then
      "server.rack"
    else if system.nixpkgs.hostPlatform.isDarwin then
      if system.dotfiles.hardware.display.macbookScreen or false then "macbook" else "macmini"
    else if system.dotfiles.desktop.enable then
      "desktopcomputer"
    else
      "server.rack";

  # A host ID derived from the label keeps the host's identity across
  # activations without storing one.
  id =
    label:
    let
      h = builtins.hashString "sha256" "rex-host:${label}";
      part = start: len: lib.substring start len h;
    in
    "host:${part 0 8}-${part 8 4}-${part 12 4}-${part 16 4}-${part 20 12}";
in
lib.concatMap (
  host:
  map (
    { home, system }:
    {
      label = host;
      id = id host;
      endpoints = [ home.dotfiles.terminal.rex.route ];
      icon = icon system;
    }
  ) (lib.filter ({ home, ... }: home.dotfiles.terminal.rex.route != null) (homesOf host))
) (lib.remove self hostNames)
