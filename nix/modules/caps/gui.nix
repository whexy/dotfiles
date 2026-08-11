# gui cap preset: machines expected to have GUI environments.
_: {
  dotfiles = {
    desktop.enable = true;
    # Touch ID / Apple Watch sudo; only has an effect on Darwin.
    security.biometricSudo.enable = true;
  };
}
