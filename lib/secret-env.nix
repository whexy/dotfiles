# Hands an agenix secret to one program's process, read on each run, so no
# shell or agent environment holds it.
{ lib }:
rec {
  # agenix secret paths are shell fragments ("${XDG_RUNTIME_DIR}/agenix/..."
  # on Linux, "$(getconf DARWIN_USER_TEMP_DIR)/agenix/..." on Darwin), so
  # they stay double-quoted and expand at run time.
  quote = path: ''"${path}"'';

  # Bash that exports `variable` from the secret at `path`. With
  # `callerHas`, a shell condition saying the caller brings its own value,
  # that value wins. `onLoad` runs after the secret is exported. A missing
  # secret stops the program when `required`, else it runs without it.
  export =
    {
      name,
      variable,
      path,
      required,
      callerHas ? null,
      onLoad ? "",
    }:
    let
      load = ''
        # -s, not -r: an interrupted decryption leaves a readable but empty
        # file.
        if [ -s ${quote path} ]; then
          ${variable}=$(<${quote path})
          export ${variable}
          ${onLoad}
        else
          echo ${lib.escapeShellArg "${name}: no ${variable} secret at "}${quote path}${
            if required then "" else lib.escapeShellArg "; running without it"
          } >&2
          ${lib.optionalString required "exit 1"}
        fi
      '';
    in
    if callerHas == null then
      load
    else
      ''
        if ! {
          ${callerHas}
        }; then
          ${load}
        fi
      '';
}
