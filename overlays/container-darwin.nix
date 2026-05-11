# Workaround: NixOS/nixpkgs#445648
# container-apiserver derives its plugin directory from the resolved binary
# location. When installed via Nix/Home Manager, the binary is symlinked into
# the user profile, causing the apiserver to look for plugins under the profile
# directory (e.g. /etc/profiles/per-user/<user>/libexec/container/plugins/)
# instead of the Nix store path where they actually live.
#
# Fix: set CONTAINER_INSTALL_ROOT so the apiserver always finds its plugins.
# Remove this overlay once the upstream package wraps the binaries itself.
final: prev:
prev.lib.optionalAttrs prev.stdenv.hostPlatform.isDarwin {
  container = prev.container.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];

    postInstall = (old.postInstall or "") + ''
      # Wrap binaries so they can find plugins regardless of symlink resolution
      for bin in $out/bin/container $out/bin/container-apiserver; do
        if [ -f "$bin" ]; then
          wrapProgram "$bin" --set CONTAINER_INSTALL_ROOT "$out"
        fi
      done
    '';
  });
}
