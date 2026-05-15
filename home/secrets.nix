{ config, ... }:
{
  age = {
    identityPaths = [ "${config.home.homeDirectory}/.config/agenix/key.txt" ];
    secrets = {
      api-keys.file = ../secrets/api-keys.age;
      nas-webdav-pass.file = ../secrets/nas-webdav-pass.age;
      cf-access-nas-client-id.file = ../secrets/cf-access-nas-client-id.age;
      cf-access-nas-client-secret.file = ../secrets/cf-access-nas-client-secret.age;
      b2-account.file = ../secrets/b2-account.age;
      b2-key.file = ../secrets/b2-key.age;
      b2-crypt-password.file = ../secrets/b2-crypt-password.age;
    };
  };
}
