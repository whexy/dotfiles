{ config, ... }:
{
  age = {
    identityPaths = [ "${config.home.homeDirectory}/.config/agenix/key.txt" ];
    secrets = {
      api-keys.file = ../secrets/api-keys.age;
      nas-webdav-pass.file = ../secrets/nas-webdav-pass.age;
    };
  };
}
