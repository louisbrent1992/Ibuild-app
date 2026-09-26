#!/usr/bin/env bash
# Generates the android/ and ios/ platform folders and applies the few
# changes iBuild needs. Safe to run more than once.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d android ] || [ ! -d ios ]; then
  flutter create . --project-name ibuild --org dev.ibuild --platforms android,ios
fi

# Release builds on Android need the INTERNET permission in the main manifest
# (Flutter only adds it to the debug and profile manifests).
MANIFEST=android/app/src/main/AndroidManifest.xml
if [ -f "$MANIFEST" ] && ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  perl -0pi -e 's#(<manifest[^>]*>)#$1\n    <uses-permission android:name="android.permission.INTERNET" />#' "$MANIFEST"
  echo "Added INTERNET permission to $MANIFEST"
fi

flutter pub get
echo "Ready. Run: flutter run"
