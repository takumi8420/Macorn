#!/bin/bash
# 配布用の Macorn.dmg を作る（Developer ID 署名 → DMG → Apple の公証 → 公証の結果を DMG に添付）。
# 普段の開発ビルドは簡易署名（-）のままにして、ここでだけ署名の設定を上書きする。
#
# 前提（一度だけ用意する）
#   - キーチェーンに「Developer ID Application: TAKUMI KON (Q9Q29NW29B)」の証明書がある
#   - 公証の資格情報を `xcrun notarytool store-credentials macorn-notary ...` で登録してある
#
# 使い方（リポジトリのルートで）
#   bash scripts/release.sh            # 署名・公証まで行う
#   bash scripts/release.sh --no-notarize   # 公証を省く（手元での確認用。他の Mac では警告が出る）
#
# 出力：build/release/Macorn-<バージョン>.dmg
set -euo pipefail

TEAM_ID="${MACORN_TEAM_ID:-Q9Q29NW29B}"
IDENTITY="${MACORN_SIGN_IDENTITY:-Developer ID Application: TAKUMI KON ($TEAM_ID)}"
NOTARY_PROFILE="${MACORN_NOTARY_PROFILE:-macorn-notary}"
NOTARIZE=1
[[ "${1:-}" == "--no-notarize" ]] && NOTARIZE=0

cd "$(dirname "$0")/.."
OUT="build/release"
DERIVED="$OUT/DerivedData"
APP="$DERIVED/Build/Products/Release/Macorn.app"

echo "== 1. Release ビルド（Developer ID で署名）"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild -project Macorn.xcodeproj -scheme Macorn -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build -quiet

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$OUT/Macorn-$VERSION.dmg"

echo "== 2. 署名を確かめる"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --verbose=2 "$APP" 2>&1 | grep -E "Authority=Developer ID Application|TeamIdentifier|Runtime"

echo "== 3. DMG を作る（Macorn.app と「アプリケーション」への近道を入れる）"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Macorn.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Macorn" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
codesign --sign "$IDENTITY" --timestamp "$DMG"

if [[ $NOTARIZE == 1 ]]; then
  echo "== 4. Apple の公証に出す（数分かかる）"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "== 5. 公証の結果を DMG に添付する"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "== 6. Gatekeeper の判定"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

shasum -a 256 "$DMG"
echo "できました: $DMG"
