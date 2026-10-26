# 変更履歴

`Macorn/` リポジトリの変更履歴。何を変えたかに加えて、きっかけ（依頼・会話）と意図・方針を残す。記載ルールは [AGENTS.md](AGENTS.md) の「変更履歴」を参照。

2026-10-26 に運用を開始した。2026-10-26 の分（要件定義から v1.0 の実装まで）は、作業したセッションの会話をもとに後から記録した。それ以前の経緯はない（このリポジトリは 2026-10-26 に作った）。

## 2026-10-26

### Macorn：タグをほかのタグの上へドラッグして階層に入れられるようにする

- **きっかけ**：konta の指摘「既存のタグを既存のタグの下に配置するなどがドラッグアンドドロップでできていない」
- **意図・方針**
  - 原因：行の間に隙間を空ける表示（.gap）では、AppKit が置き先の候補として「行の間」ばかりを出し、「行の上」をほとんど出さない。これまでの確認は置き先を直接渡す手順だったため気付けなかった
  - タグを受け取れる行（「タグ」のタグ・お気に入りやセクションに置いたタグ・タグのセクションの見出し）では、カーソルが行の真ん中あたり（上下の端 25% を除く）にあれば、その行の上に置くものとして決め直すようにした。上下の端では今までどおり行の間に入る
  - これで、タグの下の階層へ入れる・お気に入りの項目をタグへ移す・ファイルをタグへ落として付ける、のどれも行の上へのドロップで効く
  - 確認用に、カーソルを行の中のある高さに置いたときのドロップを、AppKit の候補から始めて試す手順（sbhover）を足した
- 変更 `Macorn/Sidebar/SidebarViewController.swift` — カーソルの位置で置き先を決め直す、確認用の手順
- 変更 `Macorn/App/DebugAutomation.swift` — sbhover

### Macorn：サイドバーにセクションを作るボタンを置く

- **きっかけ**：konta の依頼「セクションを作るためのボタンを別途作成してほしい」
- **意図・方針**
  - サイドバーのいちばん下に「＋ セクションを作る」を置いた（Finder・メールなど、サイドバーの追加ボタンを下に置く Mac のアプリに合わせた）。押すと名前を聞き、いちばん下にセクションを作る
  - 右クリックや設定から作る方法はそのまま残した
- 変更 `Macorn/Sidebar/SidebarViewController.swift` — 一覧の下に区切り線とボタンを置く
- 変更 `README.md`、`docs/REQUIREMENTS.md` — 操作一覧、N-04 の内容

### Macorn：セクションを最初から1つ用意する

- **きっかけ**：konta の依頼「セクションをデフォルトで一つ作成しておいてほしい」
- **意図・方針**
  - 初めて起動したとき、お気に入りのすぐ下に「マイセクション」を1つ作る。名前は仮のもので、右クリックや設定から自由に変えられる
  - 作ったことは設定に覚え、削除したら作り直さない（消したのにまた出てくるのを避けるため）。すでに自分でセクションを作っていれば何もしない
  - 構成を決めて確かめるテストでは作らないよう、作るかどうかを渡せるようにした
- 変更 `Macorn/Sidebar/SidebarStore.swift` — 最初のセクションを1度だけ作る
- 変更 `MacornTests/SidebarTests.swift` — 最初のセクションのテスト（合計 121 件）
- 変更 `AGENTS.md`、`README.md`、`docs/REQUIREMENTS.md` — 確定している前提、操作一覧、N-04 の決定事項

### Macorn：お気に入りをタグの1つにし、サイドバーに自分で作るセクションを入れる

- **きっかけ**：konta の依頼「お気に入りはもう一つのタグであって、お気に入りから別のタグへ移すこともできるようにしてほしい」。作業中に「セクションという概念も導入してほしい。セクションはサイドバー上での表面上のグルーピングであり、属性が付与されるタイプの概念ではない」。確認した結果（ドラッグは「移す」で ⌥ なら残す／「お気に入り」はふつうのタグと同じ扱い／タグそのものもお気に入りに置けるまま／今の3つのセクションは残して追加できる／1つのタグは1か所だけ）に沿って作った
- **意図・方針**
  - 前提の変更：お気に入りを「サイドバーの一覧」から「お気に入り」というタグに変えた。最初から用意したタグ（固定の ID）で、一覧のタグの列や右クリックの「タグ」にも出て、フォルダにもファイルにも付けられる。名前の変更・削除・ほかのタグの下への移動はできない。自分で「お気に入り」というタグを作っていたら、それをそのまま使う
  - サイドバーの「お気に入り」はそのタグが付いた項目の一覧で、並び順と表示名だけを設定に覚える。ほかの画面でタグを付け外しすると反映し、移動・改名で1つ外れて1つ増えたときは同じ位置のまま入れ替える
  - 今までのお気に入りは、「お気に入り」のタグを新しく作ったときに、そのタグを付けて引き継ぐ。設定ではなくタグの保存ファイルを基準にしたのは、テストのアプリが普段の設定に「引き継ぎ済み」と書いてしまい、別のタグのファイルで起動したときにお気に入りが空になったため（このとき消えたお気に入りは作業前の控えから戻した）
  - お気に入りの項目をタグへドラッグすると移る（「お気に入り」のタグが外れて置いた先のタグが付く）。⌥ を押しながらだと残す。お気に入りの色はフォルダの色分けに使わない（よく使うフォルダの多くが同じ色になるため）
  - セクション：見出しや空き場所の右クリック、設定の「サイドバー」から作り、名前の変更・削除ができる。タグ・フォルダ・ファイルを置け、置いても項目には何も付かない。削除しても中の項目やタグはそのまま
  - 1つのタグを置けるのは1か所だけにし、お気に入り・セクションの間でドラッグすると移る。フォルダ・ファイルもセクションとお気に入りの間で移せる（お気に入りから出すとタグが外れ、入れると付く）
  - 右クリックの「上へ移動」「下へ移動」が端でも押せてしまっていたのを直した（メニューの自動の有効化を切った）
  - テストと自動操作が普段のサイドバーの設定を書き換えないよう、テストでは別の保存先を使い、自動操作では `MACORN_DEFAULTS_SUITE` で保存先を指定できるようにした
- 変更 `Macorn/Model/TagStore.swift` — 「お気に入り」のタグ、付いた項目を子のタグを含めずに引く、色分けから外す、変更の知らせに送り元を付ける
- 変更 `Macorn/Sidebar/SidebarStore.swift` — お気に入りをタグに合わせる、引き継ぎ、自分で作るセクション（作る・名前の変更・削除・項目を置く・動かす・外す）、1つのタグは1か所、テスト・自動操作用の保存先
- 変更 `Macorn/Sidebar/SidebarViewController.swift` — セクションの表示、お気に入り・セクション・タグの間のドラッグ＆ドロップ（⌥ で残す）、右クリック（セクションを作る・名前の変更・削除、「セクションに置く」、表示名の変更）、ファイルのアイコン
- 変更 `Macorn/Sidebar/SidebarPrompts.swift` — セクションを作る・名前の変更・削除、表示名の変更のダイアログ
- 変更 `Macorn/Settings/SettingsView.swift` — 「サイドバー」タブにセクションを作る・名前の変更・削除
- 変更 `Macorn/Window/BrowserWindowController.swift`、`Macorn/Browser/FileBrowserViewController.swift` — ファイルもお気に入りに入れられるように
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順（mksection、sbdrop の書式）
- 変更 `MacornTests/SidebarTests.swift`、`MacornTests/TagTests.swift` — お気に入りのタグ・引き継ぎ・セクションのテスト（合計 120 件）
- 変更 `AGENTS.md`、`README.md`、`docs/REQUIREMENTS.md` — 確定している前提（前提の変更）、操作一覧、環境変数、N-04・N-05

### Macorn：サイドバーを作り直してドラッグを自然にし、タグの親子を変えられるようにする

- **きっかけ**：konta の指摘「ドラッグ＆ドロップがうまく動きません。タグがそのまま動くような演出にしてほしいです。現状変なプラスマークが出ています」。作業中に「タグに関しても親子構造などを導入したい」
- **意図・方針**
  - SwiftUI のサイドバーでは、ドラッグ中に行が動かず、カーソルに「＋」（コピーの印）が出ていた。Finder と同じ部品（NSOutlineView のソースリスト）で作り直し、ドラッグ中は置く位置の行が左右に分かれて隙間が空くようにした。サイドバーの中の並べ替えは「移動」として扱うので「＋」は出ない
  - 見た目・右クリックメニュー・選択の同期など、これまでの機能はそのまま移した
  - タグの階層（「仕事/案件A」のように / で区切る）はすでにあったが、後から親を変える手段がなかった。タグをほかのタグの上へドラッグするとその下の階層へ、「タグ」の見出しへドラッグするといちばん上へ移り、右クリックの「親のタグ」からも選べるようにした。子のタグもいっしょに移り、付けた項目はそのまま。自分や自分の子孫の下へは入れない
  - 子のあるタグは開いて表示し、閉じたタグは次に開いたときも閉じたままにする
  - マウスで実際にドラッグする確認は自動ではできないため、本物と同じ確認・処理の流れでドロップするデバッグ用の手順を用意して、アプリ上で確かめた
- 追加 `Macorn/Sidebar/SidebarViewController.swift` — 新しいサイドバー（行の見た目、ドラッグ＆ドロップ、右クリック、選択の同期、タグの開閉の記憶）
- 追加 `Macorn/Sidebar/SidebarPrompts.swift` — タグ・お気に入りの名前を聞くダイアログ（旧 `SidebarView.swift` から移した）
- 削除 `Macorn/Sidebar/SidebarView.swift` — SwiftUI のサイドバー
- 変更 `Macorn/Sidebar/SidebarStore.swift` — 見出しを最後へ移す、タグのセクションを指定の位置へ置く、お気に入りを ID で動かす
- 変更 `Macorn/Model/TagStore.swift` — タグの親を変える（`moveTag` / `canMoveTag`）
- 変更 `Macorn/Window/BrowserWindowController.swift` — 新しいサイドバーに差し替え
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順（sbdrop・sbrows）
- 変更 `MacornTests/TagTests.swift` — タグの親を変えるテスト（合計 114 件）
- 変更 `README.md`、`docs/REQUIREMENTS.md` — 操作一覧、N-04・S-07 の内容

### Macorn：ドラッグ＆ドロップでサイドバーの構成を変える

- **きっかけ**：konta の依頼「ドラッグ&ドロップでサイドバーの構成を変えられるようにしてほしい」
- **意図・方針**
  - セクションの見出しをドラッグしてほかの見出しへ置くと、その前へ移る（置き先には色の線を出す）
  - 「タグ」のタグをドラッグして、お気に入りの中へ置くとその位置にお気に入りとして入り、ほかのセクションの見出しへ置くとその前にタグのセクションができる（すでにあれば位置だけ変わる）
  - サイドバーの中のドラッグは、ファイルのドラッグと区別できるよう、決まった印の付いた文字列で受け渡す
  - 実際のマウスでのドラッグは自動では確かめられないため、構成を変える処理をテストで確かめた
- 変更 `Macorn/Sidebar/SidebarStore.swift` — 見出しの前へ移す、タグのセクションを指定の位置に作る、お気に入りのタグを指定の位置へ動かす、ドラッグで受け渡す文字列
- 変更 `Macorn/Sidebar/SidebarView.swift` — 見出しとタグをドラッグできるように、見出しとお気に入りをドロップ先に
- 変更 `MacornTests/SidebarTests.swift` — ドラッグ＆ドロップでの構成の変更のテスト（合計 113 件）
- 変更 `README.md`、`docs/REQUIREMENTS.md` — 操作一覧、N-04 の内容

### Macorn：プレビューの拡大・縮小と、サイドバーの構成の変更

- **きっかけ**：konta の依頼「html のプレビューにおいて拡大縮小などが十分にできないので修正してほしい」。作業中に「サイドバーの構成は柔軟に修正できるようにしてほしい。お気に入りとあるタグを並列に置いたり順番を変えたり」
- **意図・方針**
  - 拡大・縮小：プレビュー上部に −・倍率・＋ を置き、⌘+ / ⌘− / ⌘0 とピンチでも変えられるようにした。同じ仕組みの Markdown・PDF も対象。Markdown・HTML の倍率は覚えておく。PDF の ⌘0 はページの幅に合わせる
  - 1段階で少なくとも 5% 変わるようにした（PDF の「幅に合わせる」の倍率が段階の間にあり、⌘+ がほとんど効かないように見えたため）
  - US キーボード向けの ⌘=（隠したメニュー項目）が、ショートカットの変更の仕組みで ⌘+ と同じ項目と見なされ上書きされていたので、名前を分けた
  - サイドバー：「並列に置く」を2通りで実現した。タグをお気に入りに入れてフォルダと並べられる（ドラッグで順番も変えられる）ようにし、タグを1つのセクションとして置ける（そのタグが付いた項目が並ぶ）ようにした。セクションは見出しの右クリック（上へ・下へ・隠す）と、設定の「サイドバー」（ドラッグで並べ替え・表示の切り替え・タグのセクションの追加）で変えられる
  - テストが普段のタグ（tags.json）を書き換えないよう、スキームのテストの設定で一時ファイルを使うようにした
- 変更 `Macorn/Preview/FilePreviewController.swift`、`Macorn/Browser/FileBrowserViewController+Preview.swift`、`FileBrowserViewController.swift`、`Macorn/Model/Preferences.swift` — 拡大・縮小
- 変更 `Macorn/Sidebar/SidebarStore.swift` — お気に入りのタグ、セクションの順番・表示・タグのセクション、設定の保存先を渡せるように
- 変更 `Macorn/Sidebar/SidebarView.swift` — セクションを順番どおりに表示、見出しの右クリック、タグのセクション、お気に入りのタグの行、タグの右クリックに「お気に入りに追加」「サイドバーのセクションにする」
- 変更 `Macorn/Settings/SettingsView.swift` — 「サイドバー」タブ
- 変更 `Macorn/Window/BrowserWindowController.swift` — サイドバーからファイルを選んだら、その場所へ移動して選ぶ
- 変更 `Macorn/App/MainMenu.swift`、`Macorn/Palette/CommandCatalog.swift`、`Macorn/App/DebugAutomation.swift` — メニュー（プレビューの拡大・縮小）、確認用の手順
- 変更 `Macorn.xcodeproj/xcshareddata/xcschemes/Macorn.xcscheme` — テスト中のタグ・履歴の保存先を一時ファイルに
- 追加 `MacornTests/SidebarTests.swift` — サイドバーの構成のテスト（合計 110 件）
- 変更 `README.md`、`docs/REQUIREMENTS.md`、`AGENTS.md` — 操作一覧、N-04・N-05・S-05 の内容、確定している前提

### Macorn：タグ別の並べ替え

- **きっかけ**：konta の依頼「フォルダの並び順に関してタグ別でソートできるようにもしてほしい」
- **意図・方針**
  - 「タグ」列の見出しをクリックすると、タグごとにまとめて並べる。基準は、付いているタグのうち名前の順で最初のタグ（フォルダの色と同じタグ）。同じタグの中は名前の順
  - タグの無い項目は、昇順でも降順でも最後にまとめる（降順にしたときに、タグの無い項目が先頭に来て探しにくくならないように）
  - タグを付け外ししたら、その場で並べ直す
  - 列の見出しだけでは気づきにくいので、表示 ›「並び順」（⌃⌘1〜5、降順の切り替え）も追加した
- 変更 `Macorn/Model/FileSort.swift`、`FileEntry.swift`、`FileNode.swift`、`TagStore.swift` — タグ別の並べ替えの基準
- 変更 `Macorn/Browser/FileCellView.swift`、`FileBrowserViewController+Tags.swift` — 「タグ」列で並べ替え、付け外しで並べ直す
- 変更 `Macorn/App/MainMenu.swift`、`AppDelegate.swift`、`Macorn/Palette/CommandCatalog.swift` — 表示 ›「並び順」
- 変更 `Macorn/App/DebugAutomation.swift` — メニューのショートカットを試すときに、メニュー項目を送り手として渡す
- 変更 `MacornTests/FileSortTests.swift` — タグ別の並べ替えのテスト（合計 107 件）
- 変更 `README.md`、`docs/REQUIREMENTS.md` — 操作一覧、V-01 の内容

### Macorn：画像・PDF・動画などのプレビューと、タグを続けて付けられるメニュー

- **きっかけ**：konta の依頼「PDF や動画など視覚的に確認できるものはプレビュー表示できるようにしてほしい」。作業中に「タグをフォルダに割り振る際は複数選択全体なので、選択するごとにダイアログが閉じてしまうと不便」と依頼
- **意図・方針**
  - プレビューを画像・PDF・動画・音声・書類（Keynote・Pages・Office）にも広げた。最初はすべてクイックルックで表示したが、別のプロセスで描かれるため表示を確かめられなかったので、主な種類は macOS の部品にした（画像は NSImageView、PDF は PDFKit、動画・音声は AVKit）。それ以外の書類はクイックルック
  - 保存し直されたら読み直す（PDF は見ていたページを保つ）。別のファイルを選ぶと再生を止める。HTML の「ブラウザで開く」ボタンは、画像などでは「既定のアプリで開く」にした
  - タグ：⌥⌘G の画面は付け外ししても閉じないことを確かめたうえで、閉じてしまうのは右クリックの「タグ」メニューだと判断した。メニューの行をチェックボックスにして、続けて付け外ししてもメニューが閉じないようにした
- 変更 `Macorn/Preview/FilePreviewController.swift` — 画像・PDF・動画・書類の表示、表示する部品の切り替え
- 変更 `Macorn/Browser/FileBrowserViewController+Tags.swift` — 右クリックの「タグ」をチェックボックスの行に（`TagCheckboxMenuView`）
- 変更 `Macorn/Browser/FileBrowserViewController+Preview.swift`、`Macorn/App/MainMenu.swift`、`Macorn/Settings/SettingsView.swift`、`Macorn/App/DebugAutomation.swift` — 文言と確認用の手順
- 変更 `MacornTests/MarkdownRendererTests.swift` — プレビューの種類と表示する部品の判定のテスト（合計 106 件）
- 変更 `README.md`、`docs/REQUIREMENTS.md`、`AGENTS.md` — 操作一覧、S-05 の内容、確定している前提

### Macorn：HTML のプレビュー

- **きっかけ**：konta の依頼「html をプレビュー表示できるようにして」
- **意図・方針**
  - Markdown のプレビューと同じ場所（一覧の右）に、HTML のページをそのまま表示する。保存すると自動で表示し直す
  - ダウンロードした HTML などで勝手にスクリプトが動かないよう、スクリプトは初めは止め、プレビューの上部のボタンでそのファイルに限って動かせるようにした。読めるファイルも同じフォルダの中だけにした
  - HTML は白い背景を前提に作られていることが多いので、HTML のときだけ背景を描く
  - プレビューを Markdown 専用から「ファイルのプレビュー」に作り替えた（設定の保存先は以前のまま）
- 移動 `Macorn/Preview/MarkdownPreviewController.swift` → `Macorn/Preview/FilePreviewController.swift` — Markdown と HTML の両方を表示。スクリプトの切り替え、ブラウザで開くボタン
- 変更 `Macorn/Browser/FileBrowserViewController+Preview.swift`、`FileBrowserViewController.swift`、`Macorn/Model/Preferences.swift`、`Macorn/App/MainMenu.swift`、`Macorn/Settings/SettingsView.swift`、`Macorn/Palette/CommandCatalog.swift`、`Macorn/App/DebugAutomation.swift` — 名前の変更、HTML もプレビューの対象に、メニュー・設定の文言
- 変更 `MacornTests/MarkdownRendererTests.swift` — プレビューできるファイルの判定のテスト（合計 104 件）
- 変更 `README.md`、`docs/REQUIREMENTS.md`、`AGENTS.md` — 操作一覧、S-05 の内容、確定している前提

### Macorn：タグの件数の修正、タグの色でフォルダを塗る、余白、Markdown のプレビュー、テーマ

- **きっかけ**：konta の依頼が続けて4件。「タグをつけたがサイドバー上で数が0のまま」「タグの色などに応じてフォルダの色も変えられてほしい」「右のペインの余白がないのでギチギチに感じる」「md ファイルは VS Code のようにアプリ内でプレビュー表示されるようにしてほしい」「アプリのテーマカラーも変えられるようにしてほしい」
- **意図・方針**
  - 件数が0のままだったのは、タグの付け外しを画面に知らせていなかったため（保存はできていた）。項目の一覧も変更を知らせるようにした。あわせて、日本語の名前の表記揺れ（濁点の合成・分解）でも同じ項目として扱うようにした
  - フォルダのアイコンは、付いているタグのうち名前の順で最初のタグの色で塗る。陰影は残して色だけ置き換える。サイドバーのお気に入りも同じ色にする。設定で切れる
  - 余白：一覧の左右に余白を入れ、行の高さと列の間隔を少し広げ、パスバー・ステータスバーの内側の余白も増やした（2画面の左右とも）
  - Markdown のプレビュー：.md を1つ選ぶと一覧の右に出し、それ以外を選ぶと閉じる。保存すると読んでいた位置を保ったまま表示し直す。プロジェクトの方針（外部ライブラリなし）に合わせて、変換は自前で書いた。Markdown に書かれたスクリプトは動かさない。リンクはブラウザで開き、別の .md へのリンクはそのファイルの場所へ移る
  - テーマ：外観（macOS に合わせる・ライト・ダーク）とアクセントカラー（どんぐり色を含む9色＋自由な色）を設定で選べるようにした。選択中の行は macOS の色ではなくテーマの色で塗る
- 変更 `Macorn/Model/TagStore.swift` — 付け外しを画面に知らせる、名前の表記揺れをそろえる、フォルダの色
- 変更 `Macorn/Model/FileNode.swift`、`Macorn/Browser/FileCellView.swift`、`Macorn/Sidebar/SidebarView.swift` — タグの色で塗ったアイコン
- 変更 `Macorn/Browser/FileBrowserViewController.swift`、`PathBarView.swift`、`StatusBarView.swift`、`FilterBarView.swift` — 余白、行の高さ、一覧とプレビューを並べる、テーマの色の行
- 追加 `Macorn/Preview/MarkdownRenderer.swift` — Markdown → HTML（見出し・強調・コード・引用・リスト・チェックボックス・表・リンク・画像・front matter）
- 追加 `Macorn/Preview/MarkdownPreviewController.swift` — プレビューの表示、保存の検知、リンク
- 追加 `Macorn/Browser/FileBrowserViewController+Preview.swift` — プレビューの出し入れ（⌥⌘P）、幅の記憶、テーマの反映
- 追加 `Macorn/Settings/Theme.swift` — 外観とアクセントカラー、テーマの色で塗る行
- 変更 `Macorn/Settings/SettingsView.swift`、`Macorn/Model/Preferences.swift`、`Macorn/App/MainMenu.swift`、`AppDelegate.swift`、`DebugAutomation.swift`、`Macorn/Palette/PaletteController.swift`、`Macorn/Browser/TagEditorView.swift` — 設定（テーマ・プレビュー・フォルダの色分け）、メニュー、テーマの色
- 追加 `MacornTests/MarkdownRendererTests.swift`、変更 `MacornTests/TagTests.swift` — テスト 15 件を追加（合計 103 件）
- 変更 `README.md`、`docs/REQUIREMENTS.md`、`AGENTS.md` — 操作一覧、S-05・V-07 の内容、確定している前提

### Macorn：サイドバーの「タグ」の＋ボタンの位置を直す

- **きっかけ**：konta がスクリーンショットを添えて「タグの横のプラスボタンが端にありすぎるので修正して」と依頼
- **意図・方針**：見出しは行より右端まで広がるため、＋が件数の列より外側に出ていた。件数の列とそろうよう、右に余白を入れて内側に寄せた
- 変更 `Macorn/Sidebar/SidebarView.swift` — 「タグ」見出しの＋ボタンに右の余白を追加

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
