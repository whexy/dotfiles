#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 2 || $1 != /* || -e $1 ]]; then
  echo "usage: $0 NEW_ABSOLUTE_OUTPUT_DIRECTORY SIGNING_IDENTITY" >&2
  exit 2
fi
out=$1
identity=$2
[[ $identity != - ]] || {
  echo 'A persistent signing identity is required' >&2
  exit 2
}
source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
app="$out/Dotfiles Updater.app"
mkdir -p "$app/Contents/MacOS"
cat >"$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.whexy.dotfiles-updater</string>
<key>CFBundleName</key><string>Dotfiles Updater</string>
<key>CFBundleExecutable</key><string>dotfiles-updater-launcher</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
clang -Wall -Wextra -Werror -O2 "$source_dir/launcher.c" \
  -o "$app/Contents/MacOS/dotfiles-updater-launcher"
/usr/bin/codesign --force --sign "$identity" --timestamp=none "$app"
/usr/bin/codesign --verify --strict --verbose=2 "$app"
/usr/bin/codesign -d -r- "$app" >"$out/signing-requirement.txt" 2>&1
/usr/bin/plutil -lint "$app/Contents/Info.plist"
printf 'Built %s\nInstall as root and grant Full Disk Access before enabling the service.\n' "$app"
