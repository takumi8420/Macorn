# noxy

開発者向けに作り変えた macOS のファイルマネージャー。要件は [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) を参照。

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
| 名前を変更（複数選択なら一括） | Return |
| クイックルック | スペース |
| パスを入力（Tab で補完） | ⌘L |
| 設定 | ⌘, |

ショートカットは設定の「ショートカット」タブで変更できる。

## 必要なもの

- macOS 15 以降
- Xcode 26 以降

## ビルドと起動

Xcode で `Noxy.xcodeproj` を開き、⌘R で起動する。コマンドラインからは次のとおり。

```bash
xcodebuild -project Noxy.xcodeproj -scheme Noxy -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Noxy.app
```

テスト（77 件）:

```bash
xcodebuild -project Noxy.xcodeproj -scheme Noxy -derivedDataPath build/DerivedData test
```

ターミナルから `noxy .` で開けるようにするには、アプリのメニュー「noxy › コマンドラインツールをインストール…」を使う。

## フォルダ構成

| 場所 | 内容 |
|---|---|
| `Noxy/App` | 起動処理・メニューバー・ウィンドウとタブの管理・開発用の自動操作 |
| `Noxy/Window` | 1つのウィンドウ（サイドバー＋1〜2画面＋ツールバー）と2画面表示 |
| `Noxy/Browser` | 1つの画面（ファイル一覧・パスバー・絞り込み・ステータスバー）と、その操作 |
| `Noxy/Operations` | コピー・移動・ゴミ箱・名前変更などの実行と取り消し、進み具合の表示、クリップボード |
| `Noxy/Palette` | コマンドパレット（あいまい検索・ローマ字・フォルダ履歴） |
| `Noxy/Integration` | ターミナル・エディタ連携、パスのコピー、Git の状態 |
| `Noxy/Settings` | 設定ウィンドウ、ショートカットの変更、コマンドラインツール |
| `Noxy/Sidebar` | サイドバー |
| `Noxy/Model` | フォルダの読み込み・並べ替え・履歴・パス補完・変更監視・名前の規則・フォルダサイズ |
| `NoxyTests` | ユニットテスト |

プロジェクトは Xcode の「フォルダ同期」形式のため、`Noxy/` や `NoxyTests/` にファイルを置くだけでビルド対象になる。

## 開発用の自動操作（Debug ビルドのみ）

環境変数で操作手順を渡すと、自動で操作しながらウィンドウの画像を保存する。画面収録の許可がなくても見た目を確認できる。自動操作中はウィンドウをキーにしないので、ほかのアプリでの入力を奪わない。

```bash
NOXY_DEBUG_OUT=/tmp/shots NOXY_HISTORY_PATH=/tmp/history.sqlite NOXY_DEBUG_STEPS="go:/Applications;wait:1;state;snap:apps;quit" build/DerivedData/Build/Products/Debug/Noxy.app/Contents/MacOS/Noxy
```

| 環境変数 | 内容 |
|---|---|
| `NOXY_DEBUG_STEPS` | 操作手順（`;` 区切り）。使える手順は [DebugAutomation.swift](Noxy/App/DebugAutomation.swift) を参照 |
| `NOXY_DEBUG_OUT` | 画像の保存先 |
| `NOXY_HISTORY_PATH` | フォルダ履歴の保存先（普段の履歴を汚さないため） |
| `NOXY_DEBUG_LAUNCH_LOG` | ターミナル・エディタを実際には起動せず、起動しようとした内容をこのファイルに書く |
| `NOXY_DEBUG_COPY_DELAY_US` | コピーをわざと遅くする（進み具合の表示と中止の確認用） |
