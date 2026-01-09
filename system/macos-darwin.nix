# macOS-specific system configuration
{ ... }:
{
  system.stateVersion = 6;
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    watchIdAuth = true;
  };
}
