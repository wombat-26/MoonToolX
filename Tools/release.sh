#!/bin/zsh
# MoonToolX: Direct Distribution außerhalb des App Store
# Archiv → Developer-ID-Signatur → Notarisierung durch Apple → geheftetes .app → DMG mit Hintergrund und Programme-Alias
# Voraussetzung: in Xcode › Einstellungen › Accounts angemeldet (Team 76X3T92345).
# Aufruf aus dem Projektordner: zsh Tools/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=MoonToolX.xcodeproj
SCHEME=MoonToolX
OUT=build/release
ARCHIVE=$OUT/MoonToolX.xcarchive

rm -rf "$OUT"; mkdir -p "$OUT"

echo "▸ Archiv"
xcodebuild archive -project $PROJECT -scheme $SCHEME -configuration Release \
  -destination "generic/platform=macOS" -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet

# Version und (durch die Schema-Pre-Action soeben erhöhte) Build-Nummer aus dem Archiv
VERSION=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$ARCHIVE/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$ARCHIVE/Info.plist")
NAME="MoonToolX-$VERSION-$BUILD"
DMG=$OUT/$NAME.dmg
echo "  Version $VERSION (Build $BUILD)"

echo "▸ Developer-ID-Signatur und Upload zur Notarisierung"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist Config/ExportOptions-DeveloperID.plist \
  -exportPath "$OUT/upload" -allowProvisioningUpdates -quiet

echo "▸ Warte auf Apple (meist 1–5 Minuten)"
for i in {1..60}; do
  if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$OUT/app" -allowProvisioningUpdates -quiet >/dev/null 2>&1; then
    break
  fi
  [[ $i -eq 60 ]] && { echo "Notarisierung nach 30 Minuten noch nicht fertig."; exit 1; }
  sleep 30
done

APP="$OUT/app/MoonToolX.app"
echo "▸ Prüfung"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "▸ DMG mit Hintergrund (dmgbuild)"
VENV=build/.venv-dmg
if [[ ! -x $VENV/bin/dmgbuild ]]; then
  python3 -m venv $VENV && $VENV/bin/pip install --quiet --disable-pip-version-check dmgbuild
fi
[[ -f Config/dmg/background.tiff ]] || \
  tiffutil -cathidpicheck Config/dmg/background.png Config/dmg/background@2x.png -out Config/dmg/background.tiff
$VENV/bin/dmgbuild -s Config/dmg/settings.py \
  -D app="$APP" -D background=Config/dmg/background.tiff \
  -D volicon="$APP/Contents/Resources/AppIcon.icns" \
  "MoonToolX $VERSION" "$DMG"
ditto -c -k --keepParent "$APP" "$OUT/$NAME.zip"

echo "✓ Fertig:"
ls -lh "$DMG" "$OUT/$NAME.zip"
