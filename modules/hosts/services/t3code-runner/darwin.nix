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
  home = "/Users/${config.system.primaryUser}";
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

    # The runner ran as _t3runner with these IDs before, and nix-darwin deletes
    # no account below UID 502. Runs before nix-darwin creates the new account.
    system.activationScripts.extraActivation.text = ''
      if dscl . -read /Users/_t3runner &> /dev/null; then
        /bin/chmod -a "user:_t3runner deny list,search,readattr,readextattr,readsecurity" ${home} || true
        dscl . -delete /Users/_t3runner
      fi
      if dscl . -read /Groups/_t3runner &> /dev/null; then
        dscl . -delete /Groups/_t3runner
      fi
    '';

    # nix-darwin creates a full account, and macOS counts every full account in
    # staff, which may list and read the primary user's home.
    system.activationScripts.postActivation.text = ''
      if ! /bin/ls -led ${home} | grep -q "user:${user} deny"; then
        /bin/chmod +a "user:${user} deny list,search,readattr,readextattr,readsecurity" ${home}
      fi
    '';

    users = {
      users.${user} = {
        uid = id;
        gid = id;
        home = "/var/lib/github-runners";
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
      inherit name user;
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
