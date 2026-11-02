{
  inputs,
  perSystem,
}:

# whexy/t3code's T3 server, which reads T3CODE_DEV_MANAGED_POLICY_PATH, for
# the x86_64-linux hosts that opt in with dotfiles.t3code.fork.enable. It is
# the fork's derivation unchanged, so those hosts substitute the path
# Woodpecker pushed to ci-cache; the attributes added here leave what it
# builds alone.
let
  fork = inputs.t3code-fork.packages.x86_64-linux.t3-server;
  passthru = {
    # The browser t3code-nightly pins, for the same nightly the fork builds.
    inherit (perSystem.self.t3code-nightly) browser;
    honorsManagedPolicyPath = true;
    # flake.nix pins the t3code-fork input to a commit the fork's CI built,
    # and t3code-nightly's updater then pins sources.json to its nightly.
    updater = null;
  };
in
fork
// passthru
// {
  passthru = fork.passthru or { } // passthru;
  meta = fork.meta // {
    changelog = "https://github.com/whexy/t3code/commits/${inputs.t3code-fork.rev}";
    platforms = [ "x86_64-linux" ];
  };
}
