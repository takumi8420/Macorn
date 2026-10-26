# 変更履歴

`Macorn/` リポジトリの変更履歴。何を変えたかに加えて、きっかけ（依頼・会話）と意図・方針を残す。記載ルールは [AGENTS.md](AGENTS.md) の「変更履歴」を参照。

2026-10-26 に運用を開始した。2026-10-26 の分（要件定義から v1.0 の実装まで）は、作業したセッションの会話をもとに後から記録した。それ以前の経緯はない（このリポジトリは 2026-10-26 に作った）。

## 2026-10-26

### Macorn：タグとお気に入り

- **きっかけ**：konta の依頼「フォルダーに対してタグづけを柔軟にできるようにしてほしい。お気に入り登録も」
- **意図・方針**
  - 作る前に3点を確認した。タグの保存先は「Macorn だけのタグ」（macOS 標準のタグを推奨したが、色や階層を自由に作れる方を選ばれた）、対象は「フォルダもファイルも」、お気に入りは「サイドバーを強化」
  - 「柔軟に」に応えるため、名前・色は自由、「仕事/案件A」のように / で階層にでき、1つの項目に複数のタグを付けられるようにした。親のタグの一覧には子のタグの項目も出す
  - タグの一覧は「タグを開く場所」（`macorn-tag:///ID`）として画面で開く形にした。フォルダと同じ操作（開く・コピー・名前の変更・2画面・戻る/進む・前回の状態の復元）がそのまま使える。「ここ」に当たるフォルダがないので、新規作成とペーストは使えなくした。タグの一覧へドロップするとタグを付ける
  - Macorn の中での移動・改名ではタグのパスをその場で直し、Finder などで動かされた項目はブックマークで探し直す
  - お気に入りはフォルダだけにした。ファイルを選んで ⌃⌘T を押したときに表示中のフォルダが入ってしまう不具合を、確認中に見つけて直した
  - 確認中に普段の設定（お気に入り）を書き換えないよう、設定を退避してから試し、最後に戻した
- 追加 `Macorn/Model/TagStore.swift` — タグの保存・階層・付け外し・移動への追従
- 追加 `Macorn/Browser/FileBrowserViewController+Tags.swift` — タグの一覧の表示、タグの編集（⌥⌘G）、右クリックの「タグ」
- 追加 `Macorn/Browser/TagEditorView.swift` — タグを探す・作る・付け外す小さな画面と、設定の「タグ」タブ
- 変更 `Macorn/Sidebar/SidebarView.swift`、`SidebarStore.swift` — 「お気に入り」（ドラッグ＆ドロップで追加、表示名の変更、見つからないフォルダの表示）と「タグ」（階層、色、ドロップでタグを付ける、名前・色の変更、削除）
- 変更 `Macorn/Browser/FileCellView.swift`、`FileBrowserViewController.swift` — 一覧に「タグ」列、タグの一覧では名前の後ろに場所を表示
- 変更 `Macorn/Window/BrowserWindowController.swift` — ツールバーに ★、⌃⌘T を「お気に入りに追加・外す」に。タグの一覧のタイトル
- 変更 `Macorn/Palette/` — `#` とふつうの検索でタグを探して開けるように
- 変更 `Macorn/Operations/` — 移動・名前の変更・一括変更・取り消しのときにタグのパスを直す
- 変更 `Macorn/Settings/SettingsView.swift` — 「タグ」タブと、タブを指定して開く仕組み
- 変更 `Macorn/App/MainMenu.swift`、`DebugAutomation.swift` — メニュー（お気に入り・タグを編集）と、確認用の手順
- 追加 `MacornTests/TagTests.swift` — タグのテスト 10 件（合計 88 件）
- 変更 `README.md`、`docs/REQUIREMENTS.md`、`AGENTS.md` — 操作一覧、S-07・N-04・N-05 の内容と実装状況、確定している前提

### Macorn：アプリ名を noxy から Macorn に変更（コード・プロジェクト名・アイコンまで）

- **きっかけ**：konta がアプリを起動して「noxy.app となってしまっているのはどうしてか。修正してほしい」と依頼。アプリ名を Macorn にすることは同日に決定済みだった（下の「前提の変更」）
- **意図・方針**
  - `noxy.app` になっていたのは、製品名がターゲット名（`Noxy`）から付けられ、表示名・メニューの文言も `noxy` のままだったため
  - AGENTS.md の方針どおり、名前の変更はまとめて行った。表示名・メニュー・プロジェクト・ターゲット・フォルダ・モジュール名・バンドル ID・コマンドラインツール名・内部の識別子・開発用の環境変数（`MACORN_*`）まで Macorn にそろえた
  - バンドル ID を `dev.noxy.Noxy` から `dev.macorn.Macorn` に変えると設定の保存先が変わるため、旧い設定と `~/Library/Application Support/noxy`（フォルダ履歴）を初回起動時に引き継ぐ処理を入れた
  - アイコンは `Branding/` の AppIcon.appiconset をアセットカタログに入れた（Branding は元データとして残す）
- 移動 `Noxy/` → `Macorn/`、`NoxyTests/` → `MacornTests/`、`Noxy.xcodeproj/` → `Macorn.xcodeproj/`（スキームも `Macorn`）、`Noxy.entitlements` → `Macorn.entitlements`
- 変更 `Macorn.xcodeproj/project.pbxproj` — ターゲット名・製品名・表示名・バンドル ID・テストの接続先を Macorn に。アイコンの設定を追加
- 変更 `Macorn/` と `MacornTests/` の各ファイル — メニュー（「Macorn について」「Macorn を終了」など）・メッセージ・識別子・環境変数・`@testable import Macorn`
- 追加 `Macorn/Assets.xcassets/` — アプリアイコン（`Branding/AppIcon/AppIcon.appiconset` の複製）
- 追加 `Macorn/App/LegacyMigration.swift` — 旧名の設定・履歴の引き継ぎ（テスト 1 件を `MacornTests/ExtrasTests.swift` に追加。合計 78 件）
- 変更 `README.md`、`docs/REQUIREMENTS.md`、`AGENTS.md`、`.claude/skills/catch-up/` — 名前・パス・環境変数を Macorn に。要件定義書の本文中の例（`~/repo/hobby/noxy` など）は旧名のまま残し、冒頭に注記した

### Macorn：CHANGELOG の運用開始と catch-up スキルの作成

- **きっかけ**：konta の依頼（`/create-catch-up-skill`）。セッションごとに経緯と前提を掴んでから作業できるようにしたい
- **意図・方針**
  - 案件の区切りは「Macorn」1つにまとめた（ユーザーの選択。ほかに「アプリ開発／ブランディング」の2分割、「要件／実装／ブランディング」の3分割を提案した）
  - 案件がリポジトリ全体の1つだけなので、案件用の AGENTS.md は分けず、ルートの `AGENTS.md` に前提・関係者もまとめた。catch-up も、案件が1つのうちは最初の質問を省く
  - 指示書は `AGENTS.md` を正とし、`CLAUDE.md` は `See @AGENTS.md` の1行にした
  - CHANGELOG に「きっかけ」「意図・方針」の2行を足した。後から経緯と判断理由を追えるようにするため
  - コミットの規約が無かったので「ユーザーが明示的に指示した場合のみ」とした
- 追加 `AGENTS.md` — 全体の指示書。基本ルール、フォルダ構成、確定している前提、変更履歴の記載ルール
- 追加 `CLAUDE.md` — `AGENTS.md` の参照のみ
- 追加 `CHANGELOG.md` — 本ファイル
- 追加 `.claude/skills/catch-up/` — 現状把握スキル（`SKILL.md`、`references/sources.md`、`references/output-template.md`）

### Macorn：アプリ名を Macorn に決定（前提の変更）

- **きっかけ**：catch-up の立ち上げ時に、konta が「アプリ名は Macorn に決定。まだコードは未変更」と回答
- **意図・方針**：要件定義書では D7「アプリ名 noxy（仮決定）」だった。名前の決定を前提として記録し、コード・プロジェクト名・バンドル ID の変更は別の作業としてまとめて行う
- 変更 `docs/REQUIREMENTS.md` — 0章 D7 を「Macorn（確定）。コードはまだ noxy のまま」に

### Macorn：ブランドアセットの追加（経緯は未記録）

- **きっかけ**：このセッションの外で追加された（17:53 更新）。依頼の経緯は記録がない
- **意図・方針**：`Branding/README.md` によると、名前は Mac + Acorn（どんぐり）。円・半円・三角で組んだリスがどんぐりを抱えるアイコン（ナチュラル案）
- 追加 `Branding/` — アプリアイコン（SVG・icns・appiconset・各サイズ PNG）、ロゴ（明・暗・文字のみ）、カラーとフォントの説明

### Macorn：フォルダ名を noxy から Macorn に変更し、Claude の情報を引き継ぎ（ローカルのファイル変更なし）

- **きっかけ**：konta の依頼「フォルダ名を変更したので claude のこれまでの情報を引き継げるようにしてほしい」
- **意図・方針**：Claude のメモリと会話履歴はフォルダのパスごとに保存されるため、旧パス用の保存先から新パス用へコピーした。旧い保存先はコピー元として残した。アプリ名・コードは変えていない
- リポジトリ内の変更なし（`~/.claude-personal/projects/` の中身だけをコピー）

### Macorn：git リポジトリの作成と最初のコミット

- **きっかけ**：konta の依頼「git init して、ここまでの実装を最初のコミットにして」
- **意図・方針**：ブランチは `main`。`build/` などのビルド出力は `.gitignore` で除外した。リモートは設定せず、プッシュしていない
- 追加 `.gitignore` — ビルド出力と Xcode のユーザー別ファイルを除外

### Macorn：M2〜M6 の実装（v1.0 完成）

- **きっかけ**：konta の依頼「M2 を実装して」。作業中に「今後は最後まで自走して。マイルストーンごとの確認も不要。ループエンジニアリングで実装したい」と指示があり、M6 まで続けて進めた
- **意図・方針**
  - 各マイルストーンで「実装 → ビルド → テスト → アプリを動かして確認 → 直す」を繰り返した
  - 画面収録の許可が無い環境で見た目を確かめるため、Debug ビルドにだけ入る自動操作（`NOXY_DEBUG_STEPS`）を作った
  - 自動操作中にパレットがキーウインドウになり、利用者の入力（日本語入力の文字）を奪っていたことが分かったため、自動操作中はウィンドウをキーにしないよう直した
  - 要件の S-04「絞り込み」（MVP の必須）が M1〜M2 から漏れていたので、M6 で実装した
  - Finder と違う割り当て（⌘F は絞り込み、Return は一覧の中だけで名前の変更）と、未実装の機能は要件定義書の 13章に記録した
- 追加 `Noxy/Operations/` — コピー・移動・ゴミ箱・名前変更と取り消し、進み具合の表示、クリップボード（M2）
- 追加 `Noxy/Window/PaneContainerViewController.swift` — 2画面表示（M3）
- 追加 `Noxy/Palette/` — コマンドパレット、あいまい検索、ローマ字、フォルダ履歴（SQLite）（M4）
- 追加 `Noxy/Integration/` — ターミナル・エディタ連携、パスのコピー、Git の状態（M5）
- 追加 `Noxy/Settings/` — 設定ウィンドウ、ショートカットの変更、コマンドラインツール（M5・M6）
- 追加 `Noxy/Browser/` の各ファイル — ファイル操作・クイックルック・ドラッグ＆ドロップ・絞り込み・Vim 風のキー操作・一括名前変更・情報を見る（M2〜M6）
- 追加 `Noxy/Model/` の各ファイル — コピーの実処理、名前の規則、フォルダサイズ、一括名前変更の規則
- 追加 `Noxy.entitlements` — iTerm2 を新しいタブで開くための Apple Events
- 追加 `NoxyTests/` — ユニットテスト（合計 77 件）
- 変更 `README.md` — 進捗、主な操作、フォルダ構成、自動操作の環境変数
- 変更 `docs/REQUIREMENTS.md` — 13章「実装状況」（要件から変えた点・未実装）を追加

### Macorn：Xcode プロジェクトの作成と M1 の実装

- **きっかけ**：konta の依頼「マイルストーン M1 から実装して。Xcode プロジェクトの作成から」
- **意図・方針**
  - 追加のツール（XcodeGen など）を入れず、Xcode 16 以降の「フォルダ同期」形式でプロジェクトを手で作った。`Noxy/` にファイルを置くだけでビルド対象になる
  - 大量のファイルを並べる一覧は AppKit（NSOutlineView）、それ以外は SwiftUI にした
  - `/tmp` と `/private/tmp` を同じ場所として扱えない不具合（外部の変更が反映されない）を、realpath で比べるように直した
- 追加 `Noxy.xcodeproj/` — アプリとテストの2ターゲット、共有スキーム
- 追加 `Noxy/App/`、`Noxy/Browser/`、`Noxy/Model/`、`Noxy/Sidebar/`、`Noxy/Window/` — ウィンドウ・タブ・サイドバー・リスト表示・移動・パス入力・変更監視・前回の状態の復元
- 追加 `NoxyTests/` — 履歴・パス補完・並べ替えのテスト
- 追加 `README.md` — ビルド方法とフォルダ構成

### Macorn：要件定義書の作成と確定

- **きっかけ**：konta の依頼「Finder をアレンジしたアプリを Mac 向けに開発したい。要件を決めてほしい」。たたき台のあと「2画面表示・コマンドパレット・ターミナル連携を軸に、開発者向けで確定して」
- **意図・方針**
  - Finder の置き換えではなく併用を前提にした
  - App Store のサンドボックスではフォルダに自由にアクセスできないため、直接配布を前提にした
  - ユーザーが決めていない項目（利用者・最低 OS・料金・MVP の表示形式・アプリ名）は「仮決定」として表にまとめた
- 追加 `docs/REQUIREMENTS.md` — 要件定義書 v1.0（決定事項、機能一覧、軸の3機能の詳細、ショートカット、非機能要件、技術方針、マイルストーン）
