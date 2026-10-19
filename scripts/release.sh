#!/bin/zsh
# Builds a signed, notarized release of Wiska and its Sparkle appcast, ready to publish.
#
#   1. Bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in Wiska.xcodeproj (the build number
#      must grow: Sparkle compares it), commit and push.
#   2. Write the release notes in Markdown, then
#      scripts/release.sh NOTES.md   → build-release/dist/Wiska.zip and appcast.xml
#      (the notes are shown in Wiska's update window, and on the GitHub release)
#   3. Publish both on one GitHub release (the command is printed at the end). The app's feed is
#      releases/latest/download/appcast.xml, so the newest release is what everyone updates to.
#
# Needs, in the login Keychain:
#   - the "Developer ID Application" certificate (Xcode → Settings → Accounts → Manage Certificates);
#   - notarization credentials saved as the profile "wiska-notary":
#       xcrun notarytool store-credentials wiska-notary --apple-id <Apple ID> --team-id <team>
#   - Sparkle's EdDSA key (generate_keys). Back it up (generate_keys -x file): without it no
#     update can ever be published again.
set -euo pipefail
NOTES=${1:-}
[[ -f $NOTES ]] || { echo "Usage: scripts/release.sh NOTES.md (the release notes, in Markdown)" >&2; exit 1; }
NOTES=${NOTES:A}
ROOT=${0:A:h:h}
cd $ROOT
NOTARY_PROFILE=wiska-notary
ID=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
[[ -n $ID ]] || { echo "No Developer ID Application certificate in the Keychain (Xcode → Settings → Accounts → Manage Certificates)." >&2; exit 1; }
xcrun notarytool history --keychain-profile $NOTARY_PROFILE > /dev/null 2>&1 \
    || { echo "No notarization credentials: run xcrun notarytool store-credentials $NOTARY_PROFILE …" >&2; exit 1; }
echo "Signing as: $ID"

# Hardened runtime and a secure timestamp on every signature: notarization requires both.
sign() { codesign --force --sign "$ID" --options runtime --timestamp "$@"; }

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
sign $APP/Contents/Frameworks/whisper.framework

# Sparkle's helpers, inside out, as Sparkle's documentation says (the Downloader keeps its entitlements).
SPARKLE=$APP/Contents/Frameworks/Sparkle.framework
sign $SPARKLE/Versions/B/XPCServices/Installer.xpc
sign --preserve-metadata=entitlements $SPARKLE/Versions/B/XPCServices/Downloader.xpc
sign $SPARKLE/Versions/B/Autoupdate
sign $SPARKLE/Versions/B/Updater.app
sign $SPARKLE

# Anything else with code inside (loose libraries), then the app itself.
find $APP/Contents -type f \( -name '*.dylib' -o -name '*.so' \) -print0 | while IFS= read -r -d '' library; do
    sign "$library"
done
# Not the requirements: Xcode wrote them for the development certificate, and an app that doesn't
# meet its own designated requirement can't be given Accessibility or Input Monitoring.
sign --preserve-metadata=entitlements,flags $APP
codesign --verify --deep --strict $APP
TEAM=$(codesign -dv $APP 2>&1 | awk -F= '/^TeamIdentifier/{print $2}')
REQUIREMENT=$(codesign -d -r- $APP 2>&1 | sed -n 's/^designated => //p')
[[ $REQUIREMENT == *"subject.OU] = \"$TEAM\""* ]] || { echo "Designated requirement doesn't name team $TEAM: $REQUIREMENT" >&2; exit 1; }
codesign --verify --strict -R "=$REQUIREMENT" $APP   # the app meets its own requirement

DIST=build-release/dist
mkdir -p $DIST
ditto -c -k --norsrc --noextattr --keepParent $APP $DIST/Wiska.zip

# Apple's notary service checks the app; the ticket is then stapled to it, so it opens without a
# warning even offline.
echo "Notarizing (usually a few minutes)…"
xcrun notarytool submit $DIST/Wiska.zip --keychain-profile $NOTARY_PROFILE --wait --output-format json \
    > build-release/notary.json || true
STATUS=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status","?"))' build-release/notary.json)
if [[ $STATUS != Accepted ]]; then
    SUBMISSION=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' build-release/notary.json)
    echo "Notarization: $STATUS" >&2
    [[ -n $SUBMISSION ]] && xcrun notarytool log $SUBMISSION --keychain-profile $NOTARY_PROFILE >&2
    exit 1
fi
xcrun stapler staple $APP
spctl --assess --type execute --verbose=2 $APP 2>&1 | grep -q 'source=Notarized Developer ID' \
    || { spctl --assess --type execute --verbose=2 $APP; echo "Gatekeeper doesn't accept the app." >&2; exit 1; }
rm $DIST/Wiska.zip
ditto -c -k --norsrc --noextattr --keepParent $APP $DIST/Wiska.zip   # again, with the ticket inside
# Extended attributes would travel as ._ files that unzippers other than Finder may leave inside
# the bundle, breaking its seal: Gatekeeper then calls the app malware.
! unzip -l $DIST/Wiska.zip | grep -q '/\._' || { echo "Wiska.zip contains ._ files." >&2; exit 1; }

cp $NOTES $DIST/Wiska.md   # same name as the archive: generate_appcast embeds it as the update's notes
TOOLS=$(dirname $(find build-release/SourcePackages/artifacts -name generate_appcast -path '*/bin/*' | head -1))
$TOOLS/generate_appcast --download-url-prefix "https://github.com/jozeta/Wiska/releases/download/v$VERSION/" \
    --link https://github.com/jozeta/Wiska --embed-release-notes $DIST
grep -q 'sparkle:edSignature' $DIST/appcast.xml || { echo "appcast.xml has no EdDSA signature." >&2; exit 1; }
grep -q '<description' $DIST/appcast.xml || { echo "appcast.xml has no release notes." >&2; exit 1; }

SIZE=$(stat -f %z $DIST/Wiska.zip)
SHA=$(shasum -a 256 $DIST/Wiska.zip | cut -d' ' -f1)
echo
echo "Wiska $VERSION ($BUILD), notarized: $DIST/Wiska.zip, $SIZE bytes"
echo "SHA-256 $SHA"
echo
echo "Publish:  gh release create v$VERSION $DIST/Wiska.zip $DIST/appcast.xml --title \"Wiska $VERSION\" --notes-file $NOTES"
