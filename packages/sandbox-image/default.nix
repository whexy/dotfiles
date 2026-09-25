{
  pkgs,
  inputs,
  flake,
  perSystem,
  system,
}:

# Sandbox image for n8n-sandbox-service runners, carrying the user@sandbox home.
#
# The runner starts it as uid 1000 with HOME=/home/user, and the daemon runs
# every command under `/bin/sh -c` with a fixed PATH that ignores the Nix
# profile. /usr/local is therefore the home profile itself. Only /home/user
# and the Nix store belong to the sandbox user.
#
# Load with `$(nix build .#sandbox-image --print-out-paths) | docker load`.
let
  inherit (pkgs) lib;
  inherit (flake.legacyPackages.${system}.homeConfigurations."user@sandbox") config;
  daemon = perSystem.self.n8n-sandbox-daemon;
  homePath = config.home.path;
  homeDir = config.home.homeDirectory;

  # The TypeScript workspace n8n builds workflows in. Install scripts stay off
  # to match upstream's `npm ci --ignore-scripts`.
  workspaceSrc = "${inputs.n8n-sandbox-service}/sandbox-workspace";
  workspaceModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = workspaceSrc;
    nodejs = pkgs.nodejs_24;
    derivationArgs.npmFlags = [ "--ignore-scripts" ];
  };

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

  # Registered as valid and rooted, so the in-sandbox Nix neither refetches
  # nor garbage-collects what the image ships.
  storeRoots = [
    config.home.activationPackage
    daemon
  ]
  ++ contents;
in
pkgs.dockerTools.streamLayeredImage {
  name = "n8n-sandbox";
  tag = "latest";

  inherit contents;

  # Store layers only; the customisation layer keeps its own ownership.
  uid = 1000;
  gid = 1000;
  uname = "user";
  gname = "user";

  extraCommands = ''
    export NIX_REMOTE=local?root=$PWD USER=nobody
    ${lib.getExe' pkgs.nix "nix-store"} --load-db < ${
      pkgs.closureInfo { rootPaths = storeRoots; }
    }/registration
    ${lib.getExe pkgs.sqlite} nix/var/nix/db/db.sqlite \
      "UPDATE ValidPaths SET registrationTime = $SOURCE_DATE_EPOCH"
    mkdir -p nix/var/nix/gcroots/sandbox
    for root in ${lib.concatStringsSep " " storeRoots}; do
      ln -s "$root" nix/var/nix/gcroots/sandbox/
    done
  '';

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

    # Install roots n8n relies on, owned by the sandbox user because it
    # cannot write /usr/local: pip needs a venv and a global npm install needs
    # its own prefix. The daemon puts both bin directories on PATH.
    ${homePath}/bin/python3 -m venv ${homeDir}/venv
    printf 'prefix=${homeDir}/.npm-global\n' > ${homeDir}/.npmrc
    mkdir -p ${homeDir}/.npm-global/bin

    mkdir -p ${homeDir}/workspace/{src,chunks,node-types}
    cp -r ${workspaceSrc}/. ${workspaceModules}/node_modules ${homeDir}/workspace/
    chmod -R u+w ${homeDir}/workspace

    chown -R 1000:1000 ${homeDir} /nix/var
    chown 1000:1000 /nix
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
