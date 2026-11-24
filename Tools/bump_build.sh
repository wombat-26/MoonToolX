#!/bin/zsh
# Zählt CURRENT_PROJECT_VERSION in Config/Version.xcconfig um 1 hoch.
# Läuft als Pre-Action im Schema MoonToolX vor jedem Build (Xcode und xcodebuild -scheme).
set -e
F="${PROJECT_DIR:-${0:A:h:h}}/Config/Version.xcconfig"
N=$(awk -F' *= *' '/^CURRENT_PROJECT_VERSION/ {print $2}' "$F")
N=$((N + 1))
sed -i '' -E "s/^(CURRENT_PROJECT_VERSION *= *).*/\1$N/" "$F"
echo "MoonToolX Build $N"
