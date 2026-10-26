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
| パスをコピー | ⌥⌘C |
| 絞り込み | ⌘F または / |
| タグを編集（名前は自由、`仕事/案件A` で階層） | ⌥⌘G |
| タグの親を変える | サイドバーでタグをほかのタグへドラッグ（見出しへ置くといちばん上）、右クリック › 親のタグ |
| 並び順（名前・変更日・サイズ・種類・タグ） | ⌃⌘1〜5、列の見出しをクリック |
| お気に入りに追加・外す | ⌃⌘T、ツールバーの ★ |
| プレビュー（.md・.html・画像・PDF・動画・書類を選ぶと右に表示）の切り替え | ⌥⌘P |
| テーマ（外観・アクセントカラー） | 設定（⌘,）› 一般 |
| プレビューの拡大・縮小 | ⌘+ / ⌘− / ⌘0、トラックパッドのピンチ |
| サイドバーの構成（セクションの順番・表示、タグのセクション、お気に入りのタグ） | 見出しやタグをドラッグ＆ドロップ、見出しを右クリック、設定（⌘,）› サイドバー |
| 名前を変更（複数選択なら一括） | Return |
| クイックルック | スペース |
| パスを入力（Tab で補完） | ⌘L |
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

テスト（77 件）:

```bash
xcodebuild -project Macorn.xcodeproj -scheme Macorn -derivedDataPath build/DerivedData test
```

ターミナルから `macorn .` で開けるようにするには、アプリのメニュー「Macorn › コマンドラインツールをインストール…」を使う。

## フォルダ構成

| 場所 | 内容 |
|---|---|
| `Macorn/App` | 起動処理・メニューバー・ウィンドウとタブの管理・開発用の自動操作 |
| `Macorn/Window` | 1つのウィンドウ（サイドバー＋1〜2画面＋ツールバー）と2画面表示 |
| `Macorn/Browser` | 1つの画面（ファイル一覧・パスバー・絞り込み・ステータスバー）と、その操作 |
| `Macorn/Operations` | コピー・移動・ゴミ箱・名前変更などの実行と取り消し、進み具合の表示、クリップボード |
| `Macorn/Preview` | ファイルのプレビュー（Markdown → HTML の変換と、Markdown・HTML・画像・PDF・動画・書類の表示） |
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
| `MACORN_DEBUG_LAUNCH_LOG` | ターミナル・エディタを実際には起動せず、起動しようとした内容をこのファイルに書く |
| `MACORN_DEBUG_COPY_DELAY_US` | コピーをわざと遅くする（進み具合の表示と中止の確認用） |
