#!/bin/zsh
# Generates the Xcode project from project.yml, builds the app + widget, and optionally installs.
#   ./build.sh           build only
#   ./build.sh install   build, copy to /Applications, relaunch
set -e
cd "$(dirname "$0")"
xcodegen generate --quiet
xcodebuild -project Clausage.xcodeproj -scheme Clausage -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -quiet build
APP="build/Build/Products/Release/Clausage.app"
echo "Built $APP"

if [[ "$1" == "install" ]]; then
  pkill -x "Clausage" 2>/dev/null || true
  pkill -x "Claude Usage" 2>/dev/null || true   # the pre-rename app, if it's still around
  rm -rf "/Applications/Clausage.app"
  cp -R "$APP" /Applications/
  echo "Installed /Applications/Clausage.app"
fi
