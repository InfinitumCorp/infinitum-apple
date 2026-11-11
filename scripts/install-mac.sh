#!/bin/bash
# Builds every Infinitum Mac app on this Mac and installs it in ~/Applications/Infinitum.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/InfinitumCorp/infinitum-apple/feat/apple-apps/scripts/install-mac.sh)
#
# Needs Xcode 16.3 or newer (App Store). Asks for no passwords and signs ad hoc (no Apple ID).
# Re-running is safe: it updates the sources and replaces only the apps it builds.
set -eo pipefail

BRANCH="${INFINITUM_APPLE_BRANCH:-feat/apple-apps}"
NEXUS_BRANCH="${INFINITUM_NEXUS_BRANCH:-main}"
SRC="$HOME/src"
DEST="$HOME/Applications/Infinitum"
LOG="$SRC/infinitum-apple-build.log"
APPS=(Scalvs Metatron Architect Fabric FirmWallet Firmament Veil VeilVPN)
SIGN=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

say "Checking Xcode"
DEV="$(xcode-select -p 2>/dev/null || true)"
if [[ "$DEV" != *Xcode*.app* ]]; then
  if [ -d /Applications/Xcode.app ]; then
    fail "Xcode is installed but not selected. Run: sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept   (then run this again)"
  fi
  fail "Full Xcode is needed (not just Command Line Tools). Install Xcode from the App Store, open it once, then run this again."
fi
xcodebuild -version | head -1
XC_MAJOR="$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f1)"
XC_MINOR="$(xcodebuild -version | head -1 | awk '{print $2}' | cut -d. -f2)"
if (( XC_MAJOR < 16 || (XC_MAJOR == 16 && ${XC_MINOR:-0} < 3) )); then
  fail "Xcode 16.3 or newer is needed (found $(xcodebuild -version | head -1)). Update Xcode from the App Store."
fi

say "Checking XcodeGen"
if ! command -v xcodegen >/dev/null; then
  command -v brew >/dev/null || fail "XcodeGen is needed. Install Homebrew from https://brew.sh, then run this again."
  brew install xcodegen
fi

mkdir -p "$SRC" "$DEST"
: > "$LOG"

fetch() { # repo dir branch
  if [ -d "$2/.git" ]; then
    git -C "$2" fetch -q origin "$3" && git -C "$2" checkout -q "$3" && git -C "$2" reset -q --hard "origin/$3"
  else
    git clone -q --branch "$3" "https://github.com/InfinitumCorp/$1.git" "$2"
  fi
}

say "Getting the sources"
fetch infinitum-apple "$SRC/infinitum-apple" "$BRANCH"
cd "$SRC/infinitum-apple"
git log -1 --format='infinitum-apple %h %s'

say "Testing InfinitumKit"
(cd Packages/InfinitumKit && swift test 2>&1 | tail -3)

say "Generating the Xcode project"
xcodegen generate >>"$LOG"

declare -a OK=() FAILED=()
for app in "${APPS[@]}"; do
  say "Building $app"
  if xcodebuild -project Infinitum.xcodeproj -scheme "$app" -destination 'generic/platform=macOS' \
       -configuration Release -derivedDataPath build "${SIGN[@]}" build >>"$LOG" 2>&1; then
    rm -rf "$DEST/$app.app"
    ditto "build/Build/Products/Release/$app.app" "$DEST/$app.app"
    OK+=("$app")
  else
    grep -E "error:" "$LOG" | tail -5 || true
    FAILED+=("$app")
  fi
done

say "Building Cumulus (Mail, Drive, ID, Exchange)"
fetch infinitum-nexus "$SRC/infinitum-nexus" "$NEXUS_BRANCH"
if (cd "$SRC/infinitum-nexus/apps/cumulus-apple" && xcodebuild -project Cumulus.xcodeproj -scheme Cumulus \
     -destination 'generic/platform=macOS' -configuration Release -derivedDataPath build "${SIGN[@]}" build >>"$LOG" 2>&1); then
  rm -rf "$DEST/Cumulus.app"
  ditto "$SRC/infinitum-nexus/apps/cumulus-apple/build/Build/Products/Release/Cumulus.app" "$DEST/Cumulus.app"
  OK+=("Cumulus")
else
  grep -E "error:" "$LOG" | tail -5 || true
  FAILED+=("Cumulus")
fi

say "Done"
echo "Installed in $DEST: ${OK[*]:-none}"
[ ${#FAILED[@]} -eq 0 ] || echo "Failed: ${FAILED[*]}  (full log: $LOG)"
echo "Safari extension: open Architect, then Safari → Settings → Extensions → turn on :\\ARCHITECT\\."
echo "(Built ad hoc, so first turn on Safari → Develop → Allow Unsigned Extensions.)"
open "$DEST"
[ ${#FAILED[@]} -eq 0 ]
