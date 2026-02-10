# Nixpkgs configuration with tagging system
#
# Tags control which overlays and settings are applied:
#   - "unstable"    : Add nixpkgs-unstable as `pkgs.unstable`
#   - "llm-tools"   : Add llm-agents packages as `pkgs.llm-agents`
#   - "op-wrap"     : Add mkOpWrapped helper for 1password secret injection
#   - "op-wsl"      : Use Windows op.exe instead of native op (for WSL)
#   - "ssh-wsl"     : Use Windows ssh.exe instead of native ssh (for WSL)
#   - "op-fakeroot" : Fix 1password-cli for containerized/bwrap environments
#   - "lkl-bigmem"  : Increase LKL memory for large disk image builds (100M -> 1024M)
#
# Usage:
#   # For NixOS/Darwin modules:
#   let
#     nixpkgsSettings = import ./overlays/nixpkgs-settings.nix {
#       inherit inputs;
#       tags = [ "unstable" "llm-tools" "op-wrap" ];
#     };
#   in { imports = [ nixpkgsSettings.nixpkgsModule ]; }
#
#   # For standalone (direct nixpkgs import):
#   let
#     nixpkgsSettings = import ./overlays/nixpkgs-settings.nix {
#       inherit inputs;
#       tags = [ "unstable" "llm-tools" "op-wrap" "op-fakeroot" ];
#     };
#     pkgs = import nixpkgs {
#       inherit system;
#       inherit (nixpkgsSettings) config overlays;
#     };
#   in { ... }

{ inputs, tags }:

let
  lib = inputs.nixpkgs.lib;

  hasTag = tag: builtins.elem tag tags;

  # --- Input validation ---
  # Assert required inputs are present for each tag
  assertInput =
    name: cond: msg:
    if cond then true else throw "nixpkgs-settings: ${msg}";

  assertions = [
    (assertInput "unstable" (
      !hasTag "unstable" || inputs ? nixpkgs-unstable
    ) "tag 'unstable' requires inputs.nixpkgs-unstable")
    (assertInput "llm-tools" (
      !hasTag "llm-tools" || inputs ? llm-agents
    ) "tag 'llm-tools' requires inputs.llm-agents")
  ];

  # Force evaluation of assertions
  _ = builtins.deepSeq assertions true;

  # --- Compose Overlays Based on Tags ---
  # Order matters: op-wsl and op-fakeroot must come before op-wrap
  overlays = lib.flatten [
    (lib.optional (hasTag "lkl-bigmem") (import ./lkl-bigmem.nix))
    (lib.optional (hasTag "op-wsl") (import ./op-wsl.nix))
    (lib.optional (hasTag "ssh-wsl") (import ./ssh-wsl.nix))
    (lib.optional (hasTag "op-fakeroot") (import ./fix-1password.nix))
    (lib.optional (hasTag "op-wrap") (import ./mk-op-wrapped.nix))
    (lib.optional (hasTag "unstable") (import ./unstable.nix { inherit (inputs) nixpkgs-unstable; }))
    (lib.optional (hasTag "llm-tools") (import ./llm-tools.nix { inherit (inputs) llm-agents; }))
  ];

in
{
  # For direct nixpkgs import (standalone home-manager)
  inherit overlays;
  config = {
    allowUnfree = true;
  };

  # For NixOS/Darwin module system
  nixpkgsModule = {
    nixpkgs.config.allowUnfree = true;
    nixpkgs.overlays = overlays;
  };
}
