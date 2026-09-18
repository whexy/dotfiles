#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 4 ]]; then
  echo "usage: $0 OUTPUT_DIRECTORY SIGNING_IDENTITY USER REVISION" >&2
  exit 2
fi
out=$1
identity=$2
user=$3
revision=$4
[[ $out == /* && $out != / && $revision =~ ^[0-9]+$ && $user =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]] || {
  echo 'Expected an absolute output directory, simple username, and numeric revision' >&2
  exit 2
}
[[ ! -e $out ]] || {
  echo "Output already exists: $out" >&2
  exit 2
}
source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
# Resolve the active system's interpreter, rather than the invoking shell.
bash_path=$(head -n 1 /run/current-system/activate)
bash_path=${bash_path#\#!}
bash_path=${bash_path#/usr/bin/env -i }
[[ $bash_path == /nix/store/*/bin/bash && -x $bash_path ]] || {
  echo "Unexpected activation interpreter: $bash_path" >&2
  exit 2
}
app="$out/Dotfiles Updater Probe.app"
mkdir -p "$app/Contents/MacOS"
cat >"$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.whexy.dotfiles-updater-probe</string>
<key>CFBundleName</key><string>Dotfiles Updater Probe</string>
<key>CFBundleExecutable</key><string>fda-probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$revision</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
clang -Wall -Wextra -Werror -O2 "-DPROBE_REVISION=\"$revision\"" \
  "$source_dir/probe.c" -o "$app/Contents/MacOS/fda-probe"
/usr/bin/codesign --force --sign "$identity" --timestamp=none "$app"
/usr/bin/codesign --verify --strict --verbose=2 "$app"
/usr/bin/codesign -d -r- "$app" >"$out/signing-requirement.txt" 2>&1
cat >"$out/com.whexy.dotfiles-updater-probe.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.whexy.dotfiles-updater-probe</string>
<key>ProgramArguments</key><array>
<string>/Applications/Dotfiles Updater Probe.app/Contents/MacOS/fda-probe</string>
<string>$user</string><string>$bash_path</string>
</array>
<key>RunAtLoad</key><false/>
<key>KeepAlive</key><false/>
<key>StandardOutPath</key><string>/var/log/dotfiles-updater-probe.log</string>
<key>StandardErrorPath</key><string>/var/log/dotfiles-updater-probe.log</string>
</dict></plist>
EOF
/usr/bin/plutil -lint "$app/Contents/Info.plist" "$out/com.whexy.dotfiles-updater-probe.plist"
printf 'Built %s\nNo service installed or started.\n' "$app"
