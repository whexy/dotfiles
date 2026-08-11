# Security group: sudo, 1Password, fail2ban, biometric unlock.
{ lib, ... }:
{
  options.dotfiles.security = {
    passwordlessSudo.enable = lib.mkEnableOption "passwordless sudo for the wheel group";
    onepassword.enable = lib.mkEnableOption "1Password system integration (CLI)";
    fail2ban.enable = lib.mkEnableOption "fail2ban intrusion prevention";
    biometricSudo.enable = lib.mkEnableOption "Touch ID / Apple Watch authentication for sudo";
  };
}
