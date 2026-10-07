#!/bin/zsh
# Regenerates the Settings icon picker previews (iOS/App/IconPreviews.xcassets) from the app's .icon files.
# UIImage(named:) can't load app icons, so the picker shows these light renders instead.
set -e
cd "$(dirname "$0")/.."
IC="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
for pair in Fresh:clausage-fresh Smoked:AppIcon-Smoked Grilled:AppIcon-Grilled; do
  name=${pair%%:*}; file=${pair##*:}
  dir=iOS/App/IconPreviews.xcassets/IconPreview-$name.imageset
  for s in 2 3; do
    "$IC" iOS/App/$file.icon --export-image --output-file $dir/icon@${s}x.png \
      --platform iOS --rendition Default --width 76 --height 76 --scale $s >/dev/null
  done
done
echo "Updated iOS/App/IconPreviews.xcassets"
