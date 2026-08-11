# Security group: sudo, 1Password, fail2ban, biometric unlock.
{ lib, ... }:
{
  options.dotfiles.security = {
    passwordlessSudo.enable = lib.mkEnableOption "passwordless sudo for the wheel group";
    onepassword.enable = lib.mkEnableOption "1Password system integration (CLI)";
    onepasswordGui.enable = lib.mkEnableOption "1Password GUI (Linux: _1password-gui; macOS: Homebrew cask)";
    keyring.enable = lib.mkEnableOption "GNOME Keyring (Secret Service portal for apps, Linux)";
    fail2ban.enable = lib.mkEnableOption "fail2ban intrusion prevention";
    biometricSudo.enable = lib.mkEnableOption "Touch ID / Apple Watch authentication for sudo";
  };
}
