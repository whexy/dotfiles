# Workload secrets

All paths are in clusters-work; [cluster.md](cluster.md) says how to find it.

Plaintext never enters git or command output.

1. Register `"<name>.age".publicKeys = initOnly;` in `secrets/secrets.nix`.
   Workload secrets are readable only by the admin and `k8s-aws`.
2. Encrypt from stdin, because agenix without a TTY ignores `$EDITOR`.
   Generate app tokens with `openssl rand -hex 32`, and ask Wenxuan for values
   only they hold.

   ```sh
   printf 'APP_TOKEN=%s\n' "$value" | (cd secrets && agenix -e <name>.age)
   ```

3. Materialize the file as a Kubernetes Secret on the init node. In
   `nix/modules/nixos/k3s-server.nix`, add an option (camelCase for
   hyphenated names) and a `k8sSecrets` entry next to the existing ones:

   ```nix
   <name>.enable = lib.mkOption {
     type = lib.types.bool;
     default = false;
     description = ''
       Create the <name> Secret from agenix. Effective only on the add-on (init) node.
     '';
   };

   # in the k8sSecrets attribute set:
   <name> = lib.mkIf (cfg.deployAddons && cfg.<name>.enable) {
     namespace = "<name>";
     secretName = "<name>";
     ageFile = ../../../secrets/<name>.age;
     data.parseKeyValue = [ "APP_TOKEN" ];
   };
   ```

   Then set `<name>.enable = true;` in the `my.k3s` block of
   `nix/hosts/k8s-aws/configuration.nix`.

4. Run `just deploy-aws` before ArgoCD first syncs the workload. Pods read
   Secrets at start, so roll the Deployment after any rotation.
