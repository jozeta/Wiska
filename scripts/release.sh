#!/bin/zsh
# Builds a signed release of Wiska and its Sparkle appcast, ready to publish.
#
#   1. Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in Wiska.xcodeproj (the build number
#      must grow: Sparkle compares it), commit and push.
#   2. Write the release notes in Markdown, then
#      scripts/release.sh NOTES.md   → build-release/dist/Wiska.zip and appcast.xml
#      (the notes are shown in Wiska's update window, and on the GitHub release)
#   3. Publish both on one GitHub release (the command is printed at the end). The app's feed is
#      releases/latest/download/appcast.xml, so the newest release is what everyone updates to.
#
# Signing: the Apple Development certificate in the Keychain (no Developer ID, so not notarized),
# and Sparkle's EdDSA key, which generate_keys stored in the login Keychain. Back that key up
# (generate_keys -x file): without it no update can ever be published again.
set -euo pipefail
NOTES=${1:-}
[[ -f $NOTES ]] || { echo "Usage: scripts/release.sh NOTES.md (the release notes, in Markdown)" >&2; exit 1; }
NOTES=${NOTES:A}
ROOT=${0:A:h:h}
cd $ROOT
ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/{print $2; exit}')
[[ -n $ID ]] || { echo "No Apple Development signing identity in the Keychain." >&2; exit 1; }

rm -rf build-release
xcodebuild -project Wiska.xcodeproj -scheme Wiska -configuration Release -derivedDataPath build-release \
    DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES COPY_PHASE_STRIP=YES build > build-release.log 2>&1 \
    || { tail -20 build-release.log; exit 1; }
APP=build-release/Build/Products/Release/Wiska.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' $APP/Contents/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' $APP/Contents/Info.plist)

# whisper.cpp ships for both architectures; Wiska runs on Apple Silicon only.
WHISPER=$APP/Contents/Frameworks/whisper.framework/Versions/A/whisper
lipo -thin arm64 $WHISPER -output $WHISPER.arm64 && mv $WHISPER.arm64 $WHISPER
codesign --force --sign $ID --options runtime $APP/Contents/Frameworks/whisper.framework

# Sparkle's helpers carry Sparkle's signature: sign them as Wiska, so the installer may swap the
# app atomically (inside out, as Sparkle's documentation says).
SPARKLE=$APP/Contents/Frameworks/Sparkle.framework
codesign --force --sign $ID --options runtime $SPARKLE/Versions/B/XPCServices/Installer.xpc
codesign --force --sign $ID --options runtime --preserve-metadata=entitlements $SPARKLE/Versions/B/XPCServices/Downloader.xpc
codesign --force --sign $ID --options runtime $SPARKLE/Versions/B/Autoupdate
codesign --force --sign $ID --options runtime $SPARKLE/Versions/B/Updater.app
codesign --force --sign $ID --options runtime $SPARKLE

codesign --force --sign $ID --options runtime --preserve-metadata=entitlements,requirements,flags $APP
codesign --verify --deep --strict $APP

DIST=build-release/dist
mkdir -p $DIST
ditto -c -k --sequesterRsrc --keepParent $APP $DIST/Wiska.zip
cp $NOTES $DIST/Wiska.md   # same name as the archive: generate_appcast embeds it as the update's notes
TOOLS=$(dirname $(find build-release/SourcePackages/artifacts -name generate_appcast -path '*/bin/*' | head -1))
$TOOLS/generate_appcast --download-url-prefix "https://github.com/jozeta/Wiska/releases/download/v$VERSION/" \
    --link https://github.com/jozeta/Wiska --embed-release-notes $DIST
grep -q 'sparkle:edSignature' $DIST/appcast.xml || { echo "appcast.xml has no EdDSA signature." >&2; exit 1; }
grep -q '<description' $DIST/appcast.xml || { echo "appcast.xml has no release notes." >&2; exit 1; }

SIZE=$(stat -f %z $DIST/Wiska.zip)
SHA=$(shasum -a 256 $DIST/Wiska.zip | cut -d' ' -f1)
echo
echo "Wiska $VERSION ($BUILD): $DIST/Wiska.zip, $SIZE bytes"
echo "SHA-256 $SHA"
echo
echo "Publish:  gh release create v$VERSION $DIST/Wiska.zip $DIST/appcast.xml --title \"Wiska $VERSION\" --notes-file $NOTES"
