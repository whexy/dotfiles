{
  pkgs,
  flake,
  perSystem,
  system,
}:

# Sandbox image for n8n-sandbox-service runners, carrying the user@sandbox home.
#
# The runner starts it as uid 1000 with HOME=/home/user, and the daemon runs
# every command under `/bin/sh -c` with a fixed PATH that ignores the Nix
# profile. /usr/local is therefore the home profile itself, and /home/user
# is the only directory the sandbox can write to.
#
# Load with `$(nix build .#sandbox-image --print-out-paths) | docker load`.
let
  inherit (pkgs) lib;
  inherit (flake.legacyPackages.${system}.homeConfigurations."user@sandbox") config;
  daemon = perSystem.self.n8n-sandbox-daemon;
  homePath = config.home.path;
  homeDir = config.home.homeDirectory;
in
pkgs.dockerTools.streamLayeredImage {
  name = "n8n-sandbox";
  tag = "latest";

  # The userland a host normally provides beneath a Home Manager profile.
  contents =
    (with pkgs.dockerTools; [
      binSh
      usrBinEnv
      caCertificates
    ])
    ++ (with pkgs; [
      coreutils
      diffutils
      findutils
      gawk
      gnugrep
      gnused
      gnutar
      gzip
      bzip2
      xz
      less
      procps
      which
    ]);

  enableFakechroot = true;
  fakeRootCommands = ''
    mkdir -p /etc /tmp /root ${homeDir}
    chmod 1777 /tmp
    cat > /etc/passwd <<EOF
    root:x:0:0:root:/root:/bin/sh
    user:x:1000:1000:Sandbox User:${homeDir}:${homePath}/bin/zsh
    nobody:x:65534:65534:nobody:/var/empty:/bin/sh
    EOF
    cat > /etc/group <<EOF
    root:x:0:
    user:x:1000:
    nogroup:x:65534:
    EOF
    printf '%s\n' /bin/sh ${homePath}/bin/zsh > /etc/shells

    ln -s ${homePath} /usr/local

    # What Home Manager's linkGeneration and profile install would leave.
    cp -r ${config.home-files}/. ${homeDir}/
    chmod -R u+w ${homeDir}
    ln -s ${homePath} ${homeDir}/.nix-profile

    # Agent settings are writable files seeded by activation, not store links.
    for sync in ${homePath}/bin/*-settings-sync; do
      HOME=${homeDir} "$sync"
    done

    chown -R 1000:1000 ${homeDir}
  '';

  config = {
    Cmd = [
      (lib.getExe daemon)
      "--listen-addr"
      ":8081"
    ];
    User = "1000:1000";
    WorkingDir = homeDir;
    Env = [
      "HOME=${homeDir}"
      "PATH=/usr/local/bin:/usr/bin:/bin"
    ];
    ExposedPorts."8081/tcp" = { };
  };

  meta.platforms = lib.platforms.linux;
}
