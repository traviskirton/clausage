#!/bin/zsh
# Generates the Xcode project from project.yml, builds the app + widget, and optionally installs.
#   ./build.sh           build only
#   ./build.sh install   build, copy to /Applications, relaunch
set -e
cd "$(dirname "$0")"
xcodegen generate --quiet
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsage -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -quiet build
APP="build/Build/Products/Release/Claude Usage.app"
echo "Built $APP"

if [[ "$1" == "install" ]]; then
  pkill -x "Claude Usage" 2>/dev/null || true
  rm -rf "/Applications/Claude Usage.app"
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Claude Usage.app"
fi
