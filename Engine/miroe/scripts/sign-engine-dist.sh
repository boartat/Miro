#!/bin/zsh
# Signs a miroe engine for any Apple silicon Mac (macOS 27+), the way notarization needs it: every Mach-O file with
# a Developer ID Application identity, the hardened runtime and a secure timestamp, and the Wine loader (wine.app)
# with a Developer ID provisioning profile that grants com.apple.developer.cross-architecture-support to all devices.
# (scripts/sign-engine.sh signs with a development profile instead, for the Macs registered in it.)
#
# usage: MIROE_SIGN_ID=<Developer ID Application identity> MIROE_PROFILE=<Developer ID .provisionprofile> \
#        sign-engine-dist.sh <engine dir>
#
# The engine dir is a copy made for distribution (no build tools, headers or backups); FEX must already be in it
# (sign-engine.sh puts it there). Keep the profile and the certificate out of the repository.
#
# The loader's hardened-runtime exceptions, and why Wine needs them:
#   allow-jit                         FEX compiles x86 code at run time (MAP_JIT)
#   allow-unsigned-executable-memory  Windows programs and DLLs run from memory no Mach-O signature covers
#   disable-executable-page-protection  Wine maps .exe/.dll files and makes their code sections executable; under
#                                     the hardened runtime that failed ("failed to set 60000020 protection on
#                                     wineboot.exe section .text") and no program started
#   allow-dyld-environment-variables  Miro points DYLD_FALLBACK_LIBRARY_PATH at the engine's own FreeType and
#                                     GnuTLS (miro/lib); bin/wine needs it too, or dyld drops the variable before
#                                     it starts the loader
set -euo pipefail
engine=${1:?usage: sign-engine-dist.sh <engine dir>}
sign_id=${MIROE_SIGN_ID:?set MIROE_SIGN_ID to the Developer ID Application identity}
profile=${MIROE_PROFILE:?set MIROE_PROFILE to the Developer ID provisioning profile}
bundle_id=${MIROE_BUNDLE_ID:-app.miro.miroe}
app="$engine/lib/wine/aarch64-unix/wine.app"
[[ -d "$app" ]] || { echo "no wine.app loader in $engine"; exit 1; }

decoded=$(security cms -D -i "$profile")
[[ $(plutil -extract Entitlements.com\\.apple\\.developer\\.cross-architecture-support raw -o - - <<<"$decoded") == true ]] \
  || { echo "the profile does not grant cross-architecture-support"; exit 1; }
[[ $(plutil -extract ProvisionsAllDevices raw -o - - <<<"$decoded" 2>/dev/null) == true ]] \
  || { echo "not a Developer ID profile (it does not provision all devices)"; exit 1; }

entitlements=$(mktemp -t miroe-entitlements).plist
launcher=$(mktemp -t miroe-launcher).plist
trap 'rm -f "$entitlements" "$launcher"' EXIT
cat > "$entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.cross-architecture-support</key>
	<true/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<key>com.apple.security.cs.disable-executable-page-protection</key>
	<true/>
	<key>com.apple.security.cs.allow-dyld-environment-variables</key>
	<true/>
</dict>
</plist>
EOF
cat > "$launcher" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.allow-dyld-environment-variables</key>
	<true/>
</dict>
</plist>
EOF

# every Mach-O file but the loader's own executable, which is signed with its bundle below
count=0
while IFS= read -r -d '' file; do
  [[ $(file -b "$file") == Mach-O* ]] || continue
  [[ $file == "$app/Contents/MacOS/"* ]] && continue
  if [[ $file == "$engine/bin/wine" ]]; then
    codesign -f -s "$sign_id" --options runtime --timestamp --entitlements "$launcher" "$file"
  else
    codesign -f -s "$sign_id" --options runtime --timestamp "$file"
  fi
  count=$((count + 1))
done < <(find "$engine" -type f \( -perm -111 -o -name '*.so' -o -name '*.dylib' \) -print0)

plutil -replace CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
cp "$profile" "$app/Contents/embedded.provisionprofile"
codesign -f -s "$sign_id" --options runtime --timestamp --entitlements "$entitlements" "$app"
codesign --verify --strict --deep "$app"
echo "signed $count files and $app ($bundle_id) for distribution"
