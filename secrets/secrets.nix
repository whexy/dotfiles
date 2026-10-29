# Recipients for the agenix CLI; no Nix config imports this file.
let
  # /etc/ssh/ssh_host_ed25519_key.pub, which NixOS and nix-darwin decrypt
  # system secrets with.
  hosts = {
    deimos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEX+M4F9kvZeY0HL6nZ+pdzxmH2eUK3mrNHsWUNQhW0N";
    ellison = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGmKjt3NKyjfZ0wWugesDqfxGrDo6GK1i5g8NXttpvkF";
    golf = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLXuOJLk3WydJQdeb6LDj+vfQ+G2kUdQoI6C/ABOv58";
    mudd = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHweAJnGQrHf/t2EOAavCKDZtsjg4Q/Zt1V1PsquukPY";
    neith = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILQIARHRd1ViGxJdYPkJ7isZXOD+S2j3ItQTXKarDOc6";
    phobos = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGbhWOqXDEtfysEd61b8XX/Wr6Ven5G4OrE9Oecz74kz";
    seeley = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN4F2FWDUC2Hbm0j8ea8Uria2Vs5ELYeKbQ4GiLqxaiE";
    sheridan = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL2VhPwM8AFgc6T15gH7v+D2ZS4srKao5jOhdP6qeWbQ";
    wsl = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK+7HM6BBfFS6Mv/fYYoTzLzd6PHL/gtKmPAeQoXZbxj";
    zoozve = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIENXsMYiQGTdDoLena08gPfUEkYSd3GLCvAXBE/XEYDC";
  };

  # ~/.ssh/agenix_ed25519.pub of each non-root Home Manager user, generated on
  # that machine: the user cannot read the host key.
  users = {
    "wenxuan@mars" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMQzevRGCONPhEjcZlbH5DiTriJ5WyqWoXsFOHoYzk0o";
    "wenxuan@venus" =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMwznMOaovDAHAi2vU4cfbx4uwmuqR9pmcYA0Ve1Ab9f";
    "whexy@deimos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN3YA2Vx5EYRn2vuSid5G/BzDfK3wULoXFWf4Efd/JJU";
    "whexy@ellison" =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIETKJhd4OHRakgkAbntRTvt/4cj2oDBKKhLh55gvme/a";
    "whexy@golf" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIcZv8ImlFl7aNuRHzMiROXxkgh3D/cG2VlFF/F/dUuK";
    "whexy@mudd" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKc9WtUCHV8+FQJTvQPmrsMzN/bpRU3VG6szPOs78pl0";
    "whexy@neith" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIgWbExsQ8bBnENvE0qWKZdqIi1Ly/B4nbwoTSTGNHET";
    "whexy@phobos" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEH1m2rQSOQYLXTTT2QCkAniCSoSW09EIGB1zkfweClT";
    "whexy@seeley" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINEV9+rq4pni+ACHe0hRX10z8eCWaLTYPWxHMjv/axnI";
    "whexy@sheridan" =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE7F43UkfH7I8FMwMQqjA5YPcJ2TyQMufq2Py7d7Foml";
    "whexy@wsl" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBH3ie0J1FTRKMMyHYe4onCahqOIV+Thb9iGYvztfbwf";
    "whexy@zoozve" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPzpSG9crdyeU1CGCpO20NlG7W2SRUYOI3QSZd3lj1As";
  };

  # Root homes decrypt with their machine's host key.
  roots = {
    "root@b3srv0" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKv4HiGCUjZM6nxz/M09o+weKfVqhx6NZAvOUEurXE0o";
    "root@proxmox" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG1F40J8KZa6PZOfBPQdaFWmTZLsvEqQJSUwo4MCeame";
  };

  # Editors decrypt every file, which `agenix -r` needs to rekey from them.
  editors = {
    inherit (users) "whexy@mudd" "whexy@sheridan";
  };
  to = group: builtins.attrValues (group // editors);

  homes = users // roots;
in
{
  "beszel-token.age".publicKeys = to hosts;
  "rex-package-netrc.age".publicKeys = to hosts;

  "ai-proxy-api-key.age".publicKeys = to homes;
  "cf-access-dotfiles-id.age".publicKeys = to homes;
  "cf-access-dotfiles-secret.age".publicKeys = to homes;
  "kube-clusters-work.age".publicKeys = to homes;
  "magpie-api-key.age".publicKeys = to homes;
  "openai-api-key.age".publicKeys = to homes;
  # Homes that run a public tunnel.
  "cloudflared-cert.age".publicKeys = to (
    removeAttrs homes [
      "wenxuan@mars"
      "wenxuan@venus"
    ]
  );
  "woodpecker-token.age".publicKeys = to (removeAttrs users [ "whexy@sheridan" ]);
  # Homes that enable tooling.appStoreConnect: the Macs, which run Xcode.
  "app-store-connect-api-key.age".publicKeys = to {
    inherit (users) "whexy@golf" "whexy@sheridan";
  };
  # The Atuin module decrypts these during activation, not via age.secrets.
  "atuin-key.age".publicKeys = to users;
  "atuin-session.age".publicKeys = to users;

  # Only rclone reads these, and no home enables it.
  "b2-account.age".publicKeys = to { };
  "b2-key.age".publicKeys = to { };
  "b2-crypt-password.age".publicKeys = to { };
  "nas-webdav-pass.age".publicKeys = to { };
}
