#!/bin/zsh
# Builds SpinopelvicParams.horosplugin (arm64) and runs the geometry tests.
set -euo pipefail
cd "${0:A:h}"

HOROS=/Applications/Horos.app/Contents/MacOS/Horos
OUT=build/SpinopelvicParams.horosplugin
FLAGS=(-arch arm64 -O2 -mmacosx-version-min=11.0 -Wall)

rm -rf build
mkdir -p "$OUT/Contents/MacOS"
cp Info.plist "$OUT/Contents/Info.plist"

clang "${FLAGS[@]}" test_math.c SPMath.c -o build/test_math
build/test_math >/dev/null || { build/test_math; exit 1; }

clang "${FLAGS[@]}" -fobjc-arc -Wno-deprecated-declarations -bundle -bundle_loader "$HOROS" \
  -framework Cocoa SpinopelvicParams.m SPMath.c -o "$OUT/Contents/MacOS/SpinopelvicParams"

codesign --force --sign - "$OUT"
(cd build && ditto -c -k --keepParent SpinopelvicParams.horosplugin SpinopelvicParams.horosplugin.zip)
echo "Built $OUT"

# Installer package: files installed by Installer are not quarantined, so it works
# for people downloading the plugin without needing Terminal.
mkdir -p "build/pkgroot/Library/Application Support/Horos/Plugins"
cp -R "$OUT" "build/pkgroot/Library/Application Support/Horos/Plugins/"
pkgbuild --analyze --root build/pkgroot build/component.plist >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO build/component.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
pkgbuild --root build/pkgroot --component-plist build/component.plist --install-location / \
  --identifier com.columnaspine.horos.SpinopelvicParams --version "$VERSION" build/plugin.pkg >/dev/null
productbuild --distribution distribution.xml --resources installer --package-path build \
  "build/Instalar Parametros Espinopelvicos.pkg" >/dev/null
echo "Built installer"
