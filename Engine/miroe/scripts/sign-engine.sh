#!/bin/zsh
# Makes a built upstream ARM64 Wine engine runnable: signs the loader (wine.app) with an Apple Development identity
# and embeds a development provisioning profile that grants com.apple.developer.cross-architecture-support (needed
# for the 4 GB-below memory layout of 32-bit and x86_64 code), then installs FEX as Wine's x86 emulator.
#
# usage: MIROE_SIGN_ID=<identity SHA-1 or name> MIROE_PROFILE=<path>.provisionprofile sign-engine.sh <engine dir>
#
# The profile's App ID must match the bundle ID set here (MIROE_BUNDLE_ID, default app.miro.miroe) and must have the
# "Cross-architecture Compatibility Framework" capability; the Mac must be in the profile's device list.
# Signing uses upstream's loader/wine_arm64_entitlements.plist; the profile supplies the application identifier.
# Keep the profile and certificate out of the repository: the profile lists device UDIDs.
#
# Notes from testing (wine-11.22-280, macOS 27):
# - Create prefixes after FEX is installed: wineboot then fills C:\windows\syswow64 and copies FEX into system32.
#   A prefix made before that has no 32-bit side (Wine falls back to its built-in DLLs for missing system files
#   only while it bootstraps a prefix). Fix it once: copy xtajit.dll and xtajit64.dll into its system32, then run
#   WINEBOOTSTRAPMODE=1 wine wineboot -u
set -euo pipefail
engine=${1:?usage: sign-engine.sh <engine dir>}
sign_id=${MIROE_SIGN_ID:?set MIROE_SIGN_ID to the Apple Development identity}
profile=${MIROE_PROFILE:?set MIROE_PROFILE to the development provisioning profile}
bundle_id=${MIROE_BUNDLE_ID:-app.miro.miroe}
fex=${MIROE_FEX_DIR:-/Users/Shared/miroe-lab/engines/mullion-muma/lib/wine/aarch64-windows}
src=${MIROE_WINE_SRC:-/Users/Shared/miroe-lab/src/wine-upstream}

app="$engine/lib/wine/aarch64-unix/wine.app"
[[ -d "$app" ]] || { echo "no wine.app loader in $engine"; exit 1; }
security cms -D -i "$profile" | plutil -extract Entitlements.com\\.apple\\.developer\\.cross-architecture-support raw -o - - \
  | grep -q true || { echo "the profile does not grant cross-architecture-support"; exit 1; }

plutil -replace CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
cp "$profile" "$app/Contents/embedded.provisionprofile"
codesign -s "$sign_id" -f --entitlements "$src/loader/wine_arm64_entitlements.plist" "$app"
codesign --verify --strict "$app"

# FEX: libwow64fex.dll runs i386 code (wow64), libarm64ecfex.dll runs x86_64 code (ARM64EC)
w="$engine/lib/wine/aarch64-windows"
cp "$fex/libwow64fex.dll" "$w/xtajit.dll"
cp "$fex/libarm64ecfex.dll" "$w/xtajit64.dll"
echo "signed $app as $bundle_id; FEX installed as xtajit.dll / xtajit64.dll"
