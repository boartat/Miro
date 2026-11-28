#!/bin/zsh
# Signs a built Miro.app with a Developer ID Application identity the way notarization needs it (hardened runtime,
# secure timestamp, no get-task-allow), inside out: cabextract, the thumbnail extension, then the app.
# usage: MIRO_SIGN_ID=<Developer ID Application identity> sign_miro_release.sh <Miro.app>
# Then: ditto -c -k --keepParent Miro.app Miro.zip; xcrun notarytool submit Miro.zip --keychain-profile <profile> --wait;
#       xcrun stapler staple Miro.app; zip it again for the release.
set -euo pipefail
app=${1:?usage: sign_miro_release.sh <Miro.app>}
id=${MIRO_SIGN_ID:?set MIRO_SIGN_ID to the Developer ID Application identity}
root=${0:A:h}/..
codesign -f -s "$id" --options runtime --timestamp "$app/Contents/Resources/cabextract"
codesign -f -s "$id" --options runtime --timestamp --entitlements "$root/WhiskyThumbnail/WhiskyThumbnail.entitlements" \
  "$app/Contents/PlugIns/WhiskyThumbnail.appex"
codesign -f -s "$id" --options runtime --timestamp --entitlements "$root/Miro/Miro.entitlements" "$app"
codesign --verify --strict --deep "$app"
echo "signed $app"
