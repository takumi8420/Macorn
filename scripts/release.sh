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
#   bash scripts/release.sh --publish       # 公証まで行い、LP（site/download/Macorn.dmg）も差し替える
#
# 出力：build/release/Macorn-<バージョン>.dmg
# --publish のときは、site/index.html のバージョンとサイズ（data-release の箇所と構造化データ）、site/sitemap.xml の更新日と、
# アプリが新しい版を確かめるための site/version.json も書き換える。
# LP への公開は、そのあと main に push すると GitHub Actions が行う。
set -euo pipefail

TEAM_ID="${MACORN_TEAM_ID:-Q9Q29NW29B}"
IDENTITY="${MACORN_SIGN_IDENTITY:-Developer ID Application: TAKUMI KON ($TEAM_ID)}"
NOTARY_PROFILE="${MACORN_NOTARY_PROFILE:-macorn-notary}"
NOTARIZE=1
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --no-notarize) NOTARIZE=0 ;;
    --publish) PUBLISH=1 ;;
    *) echo "知らない指定です: $arg" >&2; exit 1 ;;
  esac
done
if [[ $PUBLISH == 1 && $NOTARIZE == 0 ]]; then
  echo "公証していない DMG は LP に載せられません（--publish と --no-notarize は同時に使えない）" >&2
  exit 1
fi

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
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
DMG="$OUT/Macorn-$VERSION.dmg"

echo "== 2. 署名を確かめる"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --verbose=2 "$APP" 2>&1 | grep -E "Authority=Developer ID Application|TeamIdentifier|Runtime"

echo "== 3. DMG を作る（Macorn.app と「アプリケーション」への近道を、ドラッグを促す背景の上に並べる）"
# 背景は scripts/dmg/make-background.swift で描いたもの。ウィンドウの見た目（背景・アイコンの位置と大きさ）は
# Finder に設定させて DMG の中（.DS_Store）に保存する。初回は「Finder を操作する」許可を求められることがある。
STAGE="$OUT/dmg"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/Macorn.app"
ln -s /Applications "$STAGE/Applications"
tiffutil -cathidpicheck scripts/dmg/background.png scripts/dmg/background@2x.png -out "$STAGE/.background/background.tiff" 2>/dev/null
RW="$OUT/Macorn-rw.dmg"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -volname "Macorn" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ -size "${SIZE_MB}m" "$RW" -quiet
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}')
osascript scripts/dmg/layout.applescript "$MOUNT"
# Finder の変更の記録は DMG に要らない（隠しファイルを表示する設定の人に見えてしまう）
rm -rf "$MOUNT/.fseventsd"
sync
hdiutil detach "$MOUNT" -quiet || { sleep 3; hdiutil detach "$MOUNT" -force -quiet; }
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" -quiet
rm -f "$RW"
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

if [[ $PUBLISH == 1 ]]; then
  echo "== 7. LP の DMG とバージョンの表記を差し替える"
  mkdir -p site/download
  cp "$DMG" site/download/Macorn.dmg
  SIZE=$(python3 -c "import os,sys; print(f'{os.path.getsize(sys.argv[1])/1000/1000:.1f} MB')" "$DMG")
  python3 - "$VERSION" "$SIZE" "$BUILD" <<'PY'
import json, re, sys
version, size, build = sys.argv[1], sys.argv[2], int(sys.argv[3])
path = "site/index.html"
html = open(path, encoding="utf-8").read()
html = re.sub(r'(<span[^>]*data-release="version"[^>]*>)[^<]*(</span>)', rf"\g<1>{version}\g<2>", html)
html = re.sub(r'(<span[^>]*data-release="size"[^>]*>)[^<]*(</span>)', rf"\g<1>{size}\g<2>", html)
# 検索エンジン向けの構造化データ（JSON-LD）の版と、サイトマップの更新日
html = re.sub(r'("softwareVersion": ")[^"]*(")', rf"\g<1>{version}\g<2>", html)
import datetime
today = datetime.date.today().isoformat()
sitemap = open("site/sitemap.xml", encoding="utf-8").read()
open("site/sitemap.xml", "w", encoding="utf-8").write(re.sub(r"<lastmod>[^<]*</lastmod>", f"<lastmod>{today}</lastmod>", sitemap))
open(path, "w", encoding="utf-8").write(html)
# アプリの「アップデートを確認…」が読む（Macorn/App/UpdateChecker.swift）
info = {
    "version": version,
    "build": build,
    "download": "https://macorn.vercel.app/download/Macorn.dmg",
    "page": "https://macorn.vercel.app/#get",
}
with open("site/version.json", "w", encoding="utf-8") as f:
    json.dump(info, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
  echo "LP を更新しました（バージョン $VERSION・$SIZE）。main に push すると公開されます"
fi
