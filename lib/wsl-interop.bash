# Windows-side lookups for the WSL wrappers around Windows programs.
#
# Sourced from bash. Each function prints only its result and returns
# non-zero when the lookup fails, so a caller can capture it and report the
# failure in its own words.
#
# Windows tools are called by absolute path: systemd user services such as
# t3code.service run without the Windows directories on PATH. The prefix
# follows wsl.wslConf.automount.root in hosts/wsl/hardware.nix.
wsl_system32=/mnt/c/Windows/System32

# A Windows environment variable that names a directory, as a WSL path.
win_env_path() {
  local value
  # /d skips cmd's AutoRun commands, whose output would join the value.
  value=$("$wsl_system32/cmd.exe" /d /c "echo %$1%" 2>/dev/null) || return 1
  value=${value//$'\r'/}
  # cmd echoes an undefined variable back unexpanded.
  [[ -n $value && $value != "%$1%" ]] || return 1
  wslpath -u "$value" 2>/dev/null
}

# The first match for a program on the Windows PATH, as a WSL path.
win_which() {
  local found
  # The $PATH: scope stops where.exe from searching the working directory
  # first.
  found=$("$wsl_system32/where.exe" "\$PATH:$1" 2>/dev/null) || return 1
  found=${found%%$'\r'*}
  [[ -n $found ]] || return 1
  wslpath -u "$found" 2>/dev/null
}

# The REG_SZ default value of a registry key, verbatim. An unset default
# reads back as reg.exe's localized "(value not set)", so callers validate
# whatever they derive from it.
win_reg_default() {
  local line
  while IFS= read -r line; do
    line=${line%$'\r'}
    # Matched on the type column because the "(Default)" label is localized.
    if [[ $line =~ [[:space:]]REG_SZ[[:space:]]{4}(.*)$ ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < <("$wsl_system32/reg.exe" query "$1" /ve 2>/dev/null)
  return 1
}
