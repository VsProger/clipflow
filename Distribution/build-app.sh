#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
app_path="$root_dir/../ClipFlow.app"

swift build --package-path "$root_dir"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$root_dir/.build/debug/ClipFlow" "$app_path/Contents/MacOS/ClipFlow"
cp "$root_dir/Distribution/Info.plist" "$app_path/Contents/Info.plist"
xcrun actool "$root_dir/Distribution/Assets.xcassets" --compile "$app_path/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$root_dir/Distribution/AppIcon-Info.plist" --output-format human-readable-text
codesign --force --sign - --timestamp=none "$app_path"
echo "Created $app_path"
