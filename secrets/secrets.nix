# Recipient config for the agenix CLI — NOT imported by any Nix config.
let
  # Generate with: age-keygen -o ~/.config/agenix/key.txt
  key = "age1tmghvzq2kq9seud5uu9hh833g0v4z2356nsqumknfnluawa6qe9qt6k886";
in
{
  "b2-account.age".publicKeys = [ key ];
  "b2-key.age".publicKeys = [ key ];
  "b2-crypt-password.age".publicKeys = [ key ];
  "nas-webdav-pass.age".publicKeys = [ key ];
  "cf-access-nas-client-id.age".publicKeys = [ key ];
  "cf-access-nas-client-secret.age".publicKeys = [ key ];
  "renpho-creds.age".publicKeys = [ key ];
  "anthropic-api-key.age".publicKeys = [ key ];
  "openai-api-key.age".publicKeys = [ key ];
  "deepseek-api-key.age".publicKeys = [ key ];
  "opencode-api-key.age".publicKeys = [ key ];
  "ai-proxy-api-key.age".publicKeys = [ key ];
  "ai-proxy-mgmt-key.age".publicKeys = [ key ];
}
