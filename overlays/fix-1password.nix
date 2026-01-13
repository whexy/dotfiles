(final: prev: {
  _1password-cli = prev._1password-cli.overrideAttrs (oldAttrs: {
    # This disables the version check that triggers the ownership error
    # in containerized/bwrap environments.
    doInstallCheck = false;
    postInstall = ''
      echo "Skipping shell completion generation to avoid bwrap ownership issues"
    '';
    nativeInstallCheckInputs = [];
  });
})
