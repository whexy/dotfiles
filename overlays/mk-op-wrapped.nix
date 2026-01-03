(
  final: prev:
  let
    lib = prev.lib;
  in
  {
    mkOpWrapped =
      package: binaries: envSecrets:
      let
        # -- Assertions --
        _a1 = lib.assertMsg (lib.isDerivation package) "mkOpWrapped: `package` must be a derivation";
        _a2 = lib.assertMsg (
          lib.isList binaries && binaries != [ ]
        ) "mkOpWrapped: `binaries` must be a non-empty list of strings";
        _a3 = lib.assertMsg (lib.isAttrs envSecrets) "mkOpWrapped: `envSecrets` must be an attrset of ENV_VAR = secretRef";
        _a4 = lib.assertMsg (lib.all lib.isString binaries) "mkOpWrapped: all entries in `binaries` must be strings";
        _a5 = lib.assertMsg (lib.all (k: lib.isString k) (
          builtins.attrNames envSecrets
        )) "mkOpWrapped: envSecrets keys must be strings (environment variable names)";
        _a6 = lib.assertMsg (lib.all (v: lib.isString v) (
          builtins.attrValues envSecrets
        )) "mkOpWrapped: envSecrets values must be strings (op:// references)";

        # -- Derived values --
        opPath = lib.makeBinPath [ prev._1password-cli ];

        envMapping = lib.concatStringsSep " " (
          lib.mapAttrsToList (name: value: ''--run 'export ${name}=$(op read "${value}")' '') envSecrets
        );

        postBuildCommand = lib.concatStringsSep "\n" (
          map (binary: ''
            if [ ! -x "$out/bin/${binary}" ]; then
              echo "mkOpWrapped: binary '$out/bin/${binary}' does not exist or is not executable" >&2
              exit 1
            fi

            wrapProgram $out/bin/${binary} \
              --prefix PATH : ${opPath} \
              --run 'op account get &>/dev/null || eval $(op signin)' \
              ${envMapping}
          '') binaries
        );

      in
      prev.symlinkJoin {
        name = "opwrapped-${lib.getName package}";
        paths = [ package ];
        nativeBuildInputs = [ prev.makeWrapper ];
        postBuild = ''
          set -euo pipefail
          ${postBuildCommand}
        '';
      };
  }
)
