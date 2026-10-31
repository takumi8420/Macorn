# Macorn

開発者向けに作り変えた macOS のファイルマネージャー。旧名は noxy（2026-10-26 に改名）。要件は [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) を参照。

## 進捗

| マイルストーン | 状態 |
|---|---|
| M1 ウィンドウ・サイドバー・リスト表示・移動 | 完了 |
| M2 基本のファイル操作・クイックルック | 完了 |
| M3 2画面表示 | 完了 |
| M4 コマンドパレット | 完了 |
| M5 ターミナル・エディタ連携 | 完了（MVP 完成） |
| M6 v1.0 の残り | 完了 |

v1.x 以降（内蔵ターミナル、カスタムコマンド、ワークスペース保存など）は未着手。詳しくは要件定義書の「13. 実装状況」を参照。

## 主な操作

| 操作 | キー |
|---|---|
| コマンドパレット（`>` コマンド、`/` `~` パス、`@` ファイル、`#` サイドバー） | ⌘K |
| 2画面表示 / もう一方の画面へ | ⌘\ / Tab |
| 反対側の画面へコピー / 移動 | F5 / F6 |
| ターミナルで開く / エディタで開く | ⌥⌘T / ⌥⌘E |
| パスをコピー | ⌥⌘C、ツールバー・パスバーの右端のボタン、右クリック（ほかの形式も） |
| 絞り込み | ⌘F または / |
| タグを編集（名前は自由、`仕事/案件A` で階層） | ⌥⌘G |
| タグの親を変える | サイドバーでタグをほかのタグの行の真ん中へドラッグ（見出しへ置くといちばん上）、右クリック › 親のタグ |
| タグの並び順を変える | サイドバーでタグを行の間（行の上下の端）へドラッグ |
| 並び順（名前・変更日・サイズ・種類・タグ） | ⌃⌘1〜5、列の見出しをクリック |
| お気に入りに追加・外す（フォルダもファイルも。「お気に入り」のタグの付け外し） | ⌃⌘T、ツールバーの ★、右クリック |
| プレビュー（.md・.html・.csv・画像・PDF・動画・書類を選ぶと右に表示）の切り替え | ⌥⌘P |
| テーマ（外観・アクセントカラー） | 設定（⌘,）› 一般 |
| プレビューの拡大・縮小 | ⌘+ / ⌘− / ⌘0、トラックパッドのピンチ |
| サイドバーの構成（セクションの順番・表示、タグのセクション、お気に入りのタグ） | 見出しやタグをドラッグ＆ドロップ、見出しを右クリック、設定（⌘,）› サイドバー |
| フォルダ・ファイルをセクションに置く | 一覧で右クリック ›「セクションに置く」（新しいセクションを作って置くこともできる） |
| セクションを作る（タグ・フォルダ・ファイルをまとめる見出し。項目には何も付かない。最初に「マイセクション」が1つある） | サイドバーのいちばん下の「＋ セクションを作る」、見出しや空き場所を右クリック ›「セクションを作る…」、設定（⌘,）› サイドバー |
| お気に入り・セクションの項目をほかのタグへ移す | 項目をタグへドラッグ（⌥ を押しながらで元の場所にも残す） |
| 名前を変更（複数選択なら一括） | Return |
| クイックルック | スペース |
| パスを入力（Tab で補完） | ⌘L、パスバーの空いている所か今いるフォルダの名前を1回クリック |
| 新規フォルダ / 新規ファイル | ⇧⌘N / ⌥⌘N、ツールバーのボタン |
| PDF・Markdown・HTML・CSV・画像・動画・音声を Macorn で開く（「このアプリケーションで開く」に出る。種類ごとに既定のアプリにもできる） | 設定（⌘,）› 連携 ›「ファイルを Macorn で開く」 |
| ほかのアプリの「Finder に表示」を Macorn で開く（フォルダの既定のアプリは macOS の制限で変えられない） | 設定（⌘,）› 連携 ›「Finder の代わりに使う」 |
| 新しいバージョンを確認し、「今すぐ更新」で入れ替えて開き直す（起動時にも確認。設定でオフにできる） | Macorn ›「アップデートを確認…」、設定（⌘,）› 一般 › アップデート |
| 設定 | ⌘, |

ショートカットは設定の「ショートカット」タブで変更できる。

## 必要なもの

- macOS 15 以降
- Xcode 26 以降

## ビルドと起動

Xcode で `Macorn.xcodeproj` を開き、⌘R で起動する。コマンドラインからは次のとおり。

```bash
xcodebuild -project Macorn.xcodeproj -scheme Macorn -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Macorn.app
```

テスト（139 件）:

```bash
xcodebuild -project Macorn.xcodeproj -scheme Macorn -derivedDataPath build/DerivedData test
```

ターミナルから `macorn .` で開けるようにするには、アプリのメニュー「Macorn › コマンドラインツールをインストール…」を使う。

## 配布用の DMG

Developer ID で署名し、Apple の公証を通した DMG を作る。ほかの Mac でも警告なしに開ける。

```bash
bash scripts/release.sh
```

- 出力は `build/release/Macorn-<バージョン>.dmg`。バージョンは Xcode の `MARKETING_VERSION`
- 普段の開発ビルドは簡易署名（`-`）のまま。署名の設定はこのスクリプトの中でだけ上書きする
- 前提：キーチェーンに「Developer ID Application: TAKUMI KON (Q9Q29NW29B)」の証明書と、公証の資格情報（`xcrun notarytool store-credentials macorn-notary …` で登録したもの）があること
- 公証は数分〜数十分かかる（初回は約35分だった）。`--no-notarize` を付けると公証を省く（手元での確認用）
- DMG を開くと、背景の矢印の左右に Macorn と「アプリケーション」が並び、ドラッグを促す。背景は `scripts/dmg/make-background.swift` で描き（`swift scripts/dmg/make-background.swift scripts/dmg`）、配置は `scripts/dmg/layout.applescript` で Finder に設定させる。初回は「Finder を操作する」許可を求められることがある
- 公証の結果は DMG に添付する。DMG から取り出したアプリは、初めて開くときに macOS がネットで公証を確かめる

LP から配る DMG を新しくするときは `--publish` を付ける。`site/download/Macorn.dmg` を差し替え、LP のバージョンとサイズの表記（`data-release` の箇所）と、アプリが新しい版を確かめる `site/version.json` も書き換える。バージョンは先に Xcode の `MARKETING_VERSION`（と `CURRENT_PROJECT_VERSION`）を上げておく。そのあと main に push すると、GitHub Actions が LP ごと公開する。

```bash
bash scripts/release.sh --publish
git add site && git commit -m "Macorn <バージョン> を公開する" && git push
```

## フォルダ構成

| 場所 | 内容 |
|---|---|
| `Macorn/App` | 起動処理・メニューバー・ウィンドウとタブの管理・開発用の自動操作 |
| `Macorn/Window` | 1つのウィンドウ（サイドバー＋1〜2画面＋ツールバー）と2画面表示 |
| `Macorn/Browser` | 1つの画面（ファイル一覧・パスバー・絞り込み・ステータスバー）と、その操作 |
| `Macorn/Operations` | コピー・移動・ゴミ箱・名前変更などの実行と取り消し、進み具合の表示、クリップボード |
| `Macorn/Preview` | ファイルのプレビュー（Markdown → HTML の変換、CSV → 表の変換と、Markdown・HTML・CSV・画像・PDF・動画・書類の表示） |
| `Macorn/Palette` | コマンドパレット（あいまい検索・ローマ字・フォルダ履歴） |
| `Macorn/Integration` | ターミナル・エディタ連携、パスのコピー、Git の状態 |
| `Macorn/Settings` | 設定ウィンドウ、ショートカットの変更、コマンドラインツール |
| `Macorn/Sidebar` | サイドバー |
| `Macorn/Model` | フォルダの読み込み・並べ替え・履歴・パス補完・変更監視・名前の規則・フォルダサイズ |
| `MacornTests` | ユニットテスト |
| `Macorn/Assets.xcassets` | アプリアイコン（元データは `Branding/`） |

プロジェクトは Xcode の「フォルダ同期」形式のため、`Macorn/` や `MacornTests/` にファイルを置くだけでビルド対象になる。

## 開発用の自動操作（Debug ビルドのみ）

環境変数で操作手順を渡すと、自動で操作しながらウィンドウの画像を保存する。画面収録の許可がなくても見た目を確認できる。自動操作中はウィンドウをキーにしないので、ほかのアプリでの入力を奪わない。

```bash
MACORN_DEBUG_OUT=/tmp/shots MACORN_HISTORY_PATH=/tmp/history.sqlite MACORN_DEBUG_STEPS="go:/Applications;wait:1;state;snap:apps;quit" build/DerivedData/Build/Products/Debug/Macorn.app/Contents/MacOS/Macorn
```

| 環境変数 | 内容 |
|---|---|
| `MACORN_DEBUG_STEPS` | 操作手順（`;` 区切り）。使える手順は [DebugAutomation.swift](Macorn/App/DebugAutomation.swift) を参照 |
| `MACORN_DEBUG_OUT` | 画像の保存先 |
| `MACORN_HISTORY_PATH` | フォルダ履歴の保存先（普段の履歴を汚さないため） |
| `MACORN_TAGS_PATH` | タグの保存先（普段のタグを汚さないため） |
| `MACORN_DEFAULTS_SUITE` | 設定の保存先（UserDefaults のスイート名。お気に入りの並び・表示の設定など、普段の設定を汚さないため） |
| `MACORN_DEBUG_LAUNCH_LOG` | ターミナル・エディタを実際には起動せず、起動しようとした内容をこのファイルに書く |
| `MACORN_MOVE_DEST` / `MACORN_MOVE_ANSWER` | 「アプリケーションへ移動」の確認用。移す先を差し替え（Debug でもこれがあれば尋ねる）、`move` / `skip` で尋ねずに答える |
| `MACORN_UPDATE_URL` | 新しい版を確かめる先（既定は https://macorn.vercel.app/version.json。`file://` も可） |
| `MACORN_UPDATE_TEAM` | 自動更新で受け入れる署名のチーム（開発用ビルドは簡易署名でチームがないため、確認のときに渡す。例 `Q9Q29NW29B`）。Debug ビルドだけで効く |
| `MACORN_DEBUG_COPY_DELAY_US` | コピーをわざと遅くする（進み具合の表示と中止の確認用） |

## 紹介動画と LP

| 場所 | 内容 |
|---|---|
| `promo/sample/make-sample.sh` | 撮影に使う架空のフォルダ一式を `/Users/Shared/MacornDemo` に作る |
| `promo/capture/` | Debug ビルドを自動操作して画面を撮る（`capture.py` と手順の `steps.txt`） |
| `promo/video/` | 紹介動画（Remotion）。場面は `src/Flow.tsx` |
| `promo/build-site-assets.sh` | LP 用の画像・動画を `site/assets/` に作る |
| `site/` | LP（静的な HTML）。https://macorn.vercel.app に公開している。ヒーローの立体図（実際のフォルダの上に整理の次元を重ねる。ドラッグで回せる）と、コンセプトの節の3段階の図は `site/dims.js` が描く |
| `.github/workflows/vercel-*.yml` | LP の公開（main への push で本番、ほかのブランチでプレビュー。`site/` に変更があるときだけ） |

```bash
bash promo/sample/make-sample.sh
python3 promo/capture/capture.py promo/capture/steps.txt promo/video/public/flow
(cd promo/video && npm install && npm run render)
bash promo/build-site-assets.sh
git push   # main に site/ の変更を push すると、GitHub Actions が LP を本番に公開する
```

画面のロック中・ディスプレイのスリープ中はウィンドウを撮れない。

GitHub Actions での公開には、リポジトリの Secrets に `VERCEL_TOKEN`（Vercel の Account Settings › Tokens で作る）・`VERCEL_ORG_ID`・`VERCEL_PROJECT_ID`（`site/.vercel/project.json` の値）が必要。手元から直接公開するときは `cd site && vercel deploy --prod`。
