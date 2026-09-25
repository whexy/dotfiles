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
# hosts/sandbox/users/user/AGENTS.md describes this environment to the agent
# and must follow changes to it.
#
# Load with `$(nix build .#sandbox-image --print-out-paths) | docker load`.
let
  inherit (pkgs) lib;
  inherit (flake.legacyPackages.${system}.homeConfigurations."user@sandbox") config;
  daemon = perSystem.self.n8n-sandbox-daemon;
  homePath = config.home.path;
  homeDir = config.home.homeDirectory;
  bash = pkgs.bashInteractive;

  # The daemon replaces the environment of every command with HOME and PATH,
  # so image ENV never reaches it. /bin/sh fills in what an unattended agent
  # needs (UTF-8, no pager, no editor, no prompts) unless the caller set it,
  # then runs bash in POSIX mode.
  shell = pkgs.runCommand "sandbox-sh" { } ''
    mkdir -p $out/bin
    ln -s ${bash}/bin/bash $out/bin/bash
    cat > $out/bin/sh <<'EOF'
    #!${bash}/bin/bash
    export LANG="''${LANG:-C.UTF-8}" TZ="''${TZ:-UTC}" TERM="''${TERM:-dumb}" \
      PAGER="''${PAGER:-cat}" GIT_PAGER="''${GIT_PAGER:-cat}" \
      EDITOR="''${EDITOR:-true}" GIT_EDITOR="''${GIT_EDITOR:-true}" \
      CI="''${CI:-1}" NO_COLOR="''${NO_COLOR:-1}" \
      NIX_PATH="''${NIX_PATH:-nixpkgs=flake:nixpkgs}"
    exec -a "$0" ${bash}/bin/bash "$@"
    EOF
    chmod +x $out/bin/sh
  '';

  # The daemon is PID 1 otherwise, and it never reaps orphaned background
  # processes, which then pile up against the runner's pids limit.
  init = lib.getExe pkgs.tini;

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
      usrBinEnv
      caCertificates
    ])
    ++ (with pkgs; [
      shell
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
    pkgs.tini
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
    user:x:1000:1000:Sandbox User:${homeDir}:/bin/bash
    nobody:x:65534:65534:nobody:/var/empty:/bin/sh
    EOF
    cat > /etc/group <<EOF
    root:x:0:
    user:x:1000:
    nogroup:x:65534:
    EOF
    printf '%s\n' /bin/sh /bin/bash > /etc/shells

    ln -s ${homePath} /usr/local

    # What Home Manager's linkGeneration and profile install would leave.
    cp -r ${config.home-files}/. ${homeDir}/
    chmod -R u+w ${homeDir}
    ln -s ${homePath} ${homeDir}/.nix-profile

    # Install roots n8n relies on, owned by the sandbox user because it
    # cannot write /usr/local: pip needs a venv and a global npm install needs
    # its own prefix. The daemon puts both bin directories on PATH.
    ${homePath}/bin/python3 -m venv ${homeDir}/venv
    printf 'prefix=${homeDir}/.npm-global\n' > ${homeDir}/.npmrc
    mkdir -p ${homeDir}/.npm-global/bin

    mkdir -p ${homeDir}/projects ${homeDir}/workspace/{src,chunks,node-types}
    cp -r ${workspaceSrc}/. ${workspaceModules}/node_modules ${homeDir}/workspace/
    chmod -R u+w ${homeDir}/workspace

    chown -R 1000:1000 ${homeDir} /nix/var
    chown 1000:1000 /nix
  '';

  config = {
    Cmd = [
      init
      "--"
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
