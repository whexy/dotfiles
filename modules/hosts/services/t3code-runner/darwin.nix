# A persistent GitHub Actions runner for whexy/t3code's ios-testflight job,
# so the archive keeps its caches between releases. The repository is public
# and a pull request can rewrite any workflow, so the workflow's own `if:` and
# `runs-on` guard nothing here; the job-started hook below is the boundary.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  name = "t3code-ios";
  user = "_github-runner";
  id = 433;
  # The service's HOME. Xcode resolves the account's home from the directory,
  # the Security framework and Node from $HOME, so both must name this.
  stateDir = "/var/lib/github-runners/${name}";
  # Not under /var: Xcode drops /private from the paths it hands build phases
  # while Node keeps it, and expo-widgets' generated imports then miss.
  workDir = "/opt/github-runners/${name}";
  home = "/Users/${config.system.primaryUser}";
  # Apple's intermediate for development and distribution certificates.
  wwdrG3 = pkgs.fetchurl {
    url = "https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer";
    hash = "sha256-3PIYeMd/QZjktGFPA9aW2JxmxmAI1CROG5kWGqyRYB8=";
  };
  workflowRef = "whexy/t3code/.github/workflows/self-hosted-build.yml@refs/heads/self-hosted-nightly";
  # The runner runs this before any step of every job it takes, and fails the
  # job when it fails. Only promoted code can reach self-hosted-nightly.
  admit = pkgs.writeShellScript "t3code-runner-admit.sh" ''
    if [[ "$GITHUB_REPOSITORY" == whexy/t3code \
      && ("$GITHUB_EVENT_NAME" == push || "$GITHUB_EVENT_NAME" == workflow_dispatch) \
      && "$GITHUB_WORKFLOW_REF" == ${lib.escapeShellArg workflowRef} \
      && "$GITHUB_JOB" == ios-testflight ]]; then
      exit 0
    fi
    echo "This runner takes only ios-testflight from ${workflowRef}, on push or dispatch;" \
      "refused $GITHUB_JOB from $GITHUB_WORKFLOW_REF on $GITHUB_EVENT_NAME." >&2
    exit 1
  '';
in
{
  config = lib.mkIf config.dotfiles.services.t3codeRunner.enable {
    # A one-hour registration token, read only while the runner has no
    # registration; afterwards it keeps its own credentials in its state dir.
    # A new token here restarts the service.
    age.secrets.github-runner-t3code = {
      file = ../../../../secrets/github-runner-t3code.age;
      owner = user;
      group = user;
      mode = "0400";
    };

    # The runner keeps the work folder it registered with in .runner, so a new
    # workDir has to be written there before launchd restarts it.
    system.activationScripts.launchd.text = lib.mkBefore ''
      install -d -o ${user} -g ${user} -m 0750 ${workDir}
      runner=${stateDir}/.runner
      if [ -f "$runner" ] && [ "$(${lib.getExe pkgs.jq} -r .workFolder "$runner")" != ${workDir} ]; then
        ${lib.getExe pkgs.jq} --arg w ${workDir} '.workFolder = $w' "$runner" > "$runner.new"
        chown ${user}:${user} "$runner.new"
        mv "$runner.new" "$runner"
      fi
    '';

    system.activationScripts.postActivation.text = ''
      # nix-darwin creates a full account, and macOS counts every full account
      # in staff, which may list and read the primary user's home.
      if ! /bin/ls -led ${home} | grep -q "user:${user} deny"; then
        /bin/chmod +a "user:${user} deny list,search,readattr,readextattr,readsecurity" ${home}
      fi
      # Without them `security` silently keeps no keychain search list or
      # default keychain, so Xcode never sees the job's signing identities.
      install -d -o ${user} -g ${user} -m 0755 ${stateDir}/Library ${stateDir}/Library/Preferences
      install -d -o ${user} -g ${user} -m 0700 ${stateDir}/Library/Keychains
      # A daemon's codesign finds chain certificates in the System keychain,
      # not in the job's own keychain, and fails with errSecInternalComponent
      # when the intermediate is missing there.
      if ! /usr/bin/security find-certificate -a -Z /Library/Keychains/System.keychain | grep -q 06EC06599F4ED0027CC58956B4D3AC1255114F35; then
        /usr/bin/security add-certificates -k /Library/Keychains/System.keychain ${wwdrG3}
      fi
    '';

    users = {
      users.${user} = {
        uid = id;
        gid = id;
        home = stateDir;
        createHome = false;
        shell = "/bin/bash";
        description = "GitHub Actions runner for whexy/t3code";
      };
      groups.${user} = {
        gid = id;
        description = "GitHub Actions runner for whexy/t3code";
      };
      knownUsers = [ user ];
      knownGroups = [ user ];
    };

    services.github-runners.${name} = {
      enable = true;
      inherit name user workDir;
      group = user;
      url = "https://github.com/whexy/t3code";
      tokenFile = config.age.secrets.github-runner-t3code.path;
      replace = true;
      extraLabels = [ "t3-testflight" ];
      extraPackages = with pkgs; [
        ccache
        cocoapods
        gh
        jq
        zstd
      ];
      extraEnvironment = {
        ACTIONS_RUNNER_HOOK_JOB_STARTED = "${admit}";
        # CocoaPods fails on a non-UTF-8 locale, which a launchd daemon has.
        LANG = "en_US.UTF-8";
      };
      serviceOverrides = {
        # Wenxuan and the simulators share this Mac; builds yield to them.
        Nice = 10;
        # launchd can start the runner before agenix writes the token, and the
        # module only restarts it on a crash.
        KeepAlive.PathState.${config.age.secrets.github-runner-t3code.path} = true;
        # A daemon has no security session of its own, and without one the
        # keychain search list finds no identity.
        SessionCreate = true;
      };
    };

    # Xcode, codesign, security and PlistBuddy live outside the Nix store.
    launchd.daemons."github-runner-${name}".path = [
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ];
  };
}
