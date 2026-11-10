# 変更履歴

`Macorn/` リポジトリの変更履歴。何を変えたかに加えて、きっかけ（依頼・会話）と意図・方針を残す。記載ルールは [AGENTS.md](AGENTS.md) の「変更履歴」を参照。

2026-10-26 に運用を開始した。2026-10-26 の分（要件定義から v1.0 の実装まで）は、作業したセッションの会話をもとに後から記録した。それ以前の経緯はない（このリポジトリは 2026-10-26 に作った）。

## 2026-11-10

### Macorn：アプリのリポジトリを公開する

- **きっかけ**：konta の依頼（2026-11-10）「公開して」（アプリのリポジトリを分け、OSS 用に整えたのを受けて）
- **意図・方針**：takumi8420/Macorn を公開に切り替えた。あわせて、非公開の脆弱性報告を有効にし、main の強制的な上書きと削除を止め（ルールセット「main を守る」）、説明・ホームページ（https://macorn.app）・トピック（macos・swift・file-manager・finder-alternative・appkit・swiftui・developer-tools）を設定した。サインインせずに見て、リポジトリが公開され MIT ライセンスと認識されていること、LP のリポジトリと書き換え前のコミットは見えないことを確かめた
- 変更 `AGENTS.md` — OSS の前提を「公開済み」にし、脆弱性報告と main の保護を書き足す

### Macorn：アプリを OSS 用の新しいリポジトリに分け、LP は別のリポジトリにする

- **きっかけ**：konta の質問・依頼（2026-11-10）「そもそも現状、LP とアプリが同じレポジトリで管理されていますか？」→「アプリの方を新しいレポジトリにして OSS 用に整理したい」。分け方は「今のを LP 用に改名」、履歴は「アプリの分だけ引き継ぐ」、CHANGELOG と AGENTS.md は「入れる」を選択
- **意図・方針**：書き換え前のコミットが古いリポジトリに番号で残るため、公開するリポジトリは新しく作り、会社名を消したあとの履歴からアプリのファイルの分だけを取り出して入れた（`git filter-repo --path`。DMG と紹介動画が入らないので、履歴は 115MB → 5MB）。それまでのリポジトリは `takumi8420/macorn-site` に改名し、LP・紹介動画・Zenn の原稿を置く非公開のリポジトリにした（公開の仕組みと Vercel の Secrets をそのまま使える）。手元では2つを隣り合うフォルダ（`Macorn` と `macorn-site`）に置く
  - 新しい版を出す手順は変えない。`scripts/release.sh --publish` が、隣の LP のリポジトリ（違う場所なら `MACORN_SITE_DIR`）の DMG・版の表記・`version.json` を書き換える。見つからなければ止まる
  - LP の `version.json` とアプリの版がそろっているかのテストは、LP のリポジトリが隣にあるときだけ動かす（アプリだけを取り出した人の手元では飛ばす）
- 削除 `site/`・`promo/`・`.github/workflows/`・`vercel.json`・`.claude/launch.json` — LP のリポジトリへ移った（このリポジトリの履歴からも外した）
- 変更 `scripts/release.sh` — LP の書き込み先を、隣の LP のリポジトリにする
- 変更 `MacornTests/UpdateCheckerTests.swift` — LP の `version.json` のテストを、LP のリポジトリが隣にあるときだけにする
- 変更 `Macorn/App/UpdateChecker.swift` — `version.json` の置き場の説明を直す
- 変更 `README.md` — 公開の手順と「紹介動画と LP」の節を、LP のリポジトリを使う形に書き直す
- 変更 `AGENTS.md` — フォルダ構成から LP と素材を外し、LP のリポジトリへの案内・公開の手順・関連リンクを直す。LP の書き方の前提（Finder の代わり・リリースノート）は LP のリポジトリの AGENTS.md へ移した
- 変更 `.gitignore` — 紹介動画の行を外す

### Macorn：公開の前に、会社名と仕事のタグ名を履歴から消す

- **きっかけ**：konta の依頼（2026-11-10）「改めて、公開しても大丈夫な情報しかないか網羅的に確認して問題なければ公開してほしい」→ 点検で勤め先の会社名と仕事のタグ名が見つかり、「履歴からも消す」を選択
- **意図・方針**：点検の範囲は、履歴の全ファイルの版（911）・全コミットのメッセージと作者・画像と動画・GitHub 上の Issue／PR／リリース／Actions の記録。秘密情報（キー・トークン・パスワード）と、メールアドレス・電話番号・実在のファイル名の写った画面はなかった。会社名と仕事のタグ名だけが CHANGELOG（7か所）とコードのコメント（1か所）に残っていたので、`git filter-repo` で全履歴の該当語を置き換え（どれも架空の名前に置き換えた）、GitHub の main を上書きした。コミットの数（87）・画像や DMG などのバイナリは変わっていない。依頼の文面の引用も、この語だけ置き換えている。書き換える前の履歴は、リポジトリの外（`../Macorn-before-rewrite-2026-11-10.bundle`）に控えてある
- 変更（全履歴）`CHANGELOG.md`・`Macorn/Sidebar/SidebarViewController.swift` — 会社名とタグ名を、架空の名前に置き換える

### Macorn：MIT ライセンスで OSS にする準備をする

- **きっかけ**：konta の質問（2026-11-10）「oss にしようかと考えていますが、必要な手順はありますか？」→ 手順の説明を受けて「MIT で準備して」
- **意図・方針**：公開に切り替える前に必要なものをそろえた。リポジトリの公開（非公開 → 公開）はまだ行わない（取り消せないため、改めて確認する）
  - 公開前の点検：過去の全コミットに、API キー・トークン・秘密鍵は見つからなかった。Vercel のトークンは GitHub の Secrets にあり、公開の仕組みは自分のリポジトリへの push でだけ動く（フォークからは動かない）。コミットのメールは GitHub の匿名アドレス。氏名とチーム ID は配布している DMG の署名からも読めるので残す
  - 名前とアイコン・ロゴは、ライセンスの対象外として、配るときに使わないでもらう形にした（コードは自由に使える）
  - まっさらに取り出したリポジトリで、証明書なしにビルドでき（簡易署名）、テスト 201 件が通ることを確かめた
- 追加 `LICENSE` — MIT ライセンス（Copyright (c) 2026 Takumi Kon）
- 追加 `SECURITY.md` — 脆弱性は GitHub の非公開の報告で受けること、更新の入れ替えで確かめていること（英語・日本語）
- 変更 `README.md` — 冒頭に英語の紹介・入手先・ビルド方法・ライセンスを足し、末尾にライセンスの節を足す。配布用の DMG は作者だけが作ることを書く。テストの件数・実装状況の古い記載を直す
- 変更 `AGENTS.md` — 確定している前提に「MIT で OSS にする」を足し、フォルダ構成に `LICENSE`・`SECURITY.md` を足す

### Macorn：バージョン 0.3.25 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-10）「公開まで進めて」（絞り込みの欄を初めから出しておくようにしたのを受けて）
- **意図・方針**：0.3.24 → 0.3.25（ビルド番号は 27 → 28）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた（`sitemap.xml` の更新日は今日のままで変わらない）。リリースノートのいちばん上に 0.3.25 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — 版を 0.3.25（ビルド 28）にする
- 変更 `site/download/Macorn.dmg`・`site/index.html`・`site/version.json` — 0.3.25 に差し替える（release.sh が書く）
- 変更 `site/releases/index.html` — 0.3.25 のリリースノートを足し、「最新」を付け替える

### Macorn：絞り込みの欄を、初めから一覧の上に出しておく

- **きっかけ**：konta の依頼（2026-11-10）「検索機能ですが、デフォルトで検索バーを出しておいて欲しい」
- **意図・方針**：これまでは ⌘F・`/` を押したときだけ欄が出ていた。欄をいつも一覧の上に出しておき、そのままクリックして打てるようにした。設定（一般 › 絞り込みの欄をいつも一覧の上に出す）で、使うときだけ出す形にも戻せる。初めはオン
  - 起動時に一覧のキー入力を奪わないよう、いつも出しているときは、欄が出てきてもフォーカスを移さない。⌘F・`/` で入力欄へ移る
  - 何も打っていないときは「×」を出さず、案内に「（⌘F）」を添える。欄を直接クリックして打ったときも絞り込み中として扱い、別のフォルダへ移ったら解く
  - あわせて、欄を隠しているときに、起動時に一覧のフォーカスが外れていたのを直した（隠れた入力欄がフォーカスを取ろうとしていた）
- 変更 `Macorn/Browser/FileBrowserViewController+Keyboard.swift`・`Macorn/Browser/FileBrowserViewController.swift` — 欄を出すかを設定と絞り込みの状態で決める。設定の変更をその場で反映する
- 変更 `Macorn/Browser/FilterBarView.swift` — いつも出しているときの案内・「×」・フォーカスの扱い
- 変更 `Macorn/Browser/PaneState.swift`・`Macorn/Model/Preferences.swift`・`Macorn/Settings/SettingsView.swift` — 「絞り込みの欄をいつも出す」の設定
- 変更 `Macorn/App/DebugAutomation.swift` — 自動操作の手順 `filterbar`（欄の高さ・フォーカスを出す）を足す
- 変更 `docs/REQUIREMENTS.md` — S-04 に、欄をいつも出しておくことを足す

### Macorn：Zenn の記事を 11月10日 7:00 に予約公開する

- **きっかけ**：konta の依頼（2026-11-10 深夜）「明日、火曜の朝7時で予約公開したい」→ Zenn の「公開前のチェック」（投稿内容とコミュニティガイドラインの確認）を代わりに確定することに「確定して」
- **意図・方針**：依頼は火曜の 1時過ぎだったため、「明日、火曜の朝7時」は 2026年11月10日（火）7:00 と受け取った。Zenn の編集画面で公開予約を有効にして日時を入れ、確定した。「2026年11月10日 07:00 (JST) に公開予約されています」と出ることを確かめた。原稿の front matter も、Zenn CLI の書き方（`published: true` と `published_at`）に合わせた
- 変更 `promo/zenn/macorn-intro.md` — 公開の予約日時を書く

### Macorn：Zenn の記事のタイトルとトピックを、検索されやすい形にする

- **きっかけ**：konta の依頼（2026-11-10）「キーワードをもう少し充足させたい」→ トピックは「Finder を入れる」、タイトルにも「Finder の代わり」を「入れる」を選択
- **意図・方針**：Zenn のトピックは5つまでで、すでに埋まっていたため、数ではなく中身を入れ替えた。記事数の少ない「開発環境」（896）と「terminal」（864）を外し、Git の節がある「git」（5,436）と、「Finder の代わり」で探す人に届く「finder」を足した。タイトルは LP と同じく「Finder の代わり」を先頭に置き、Zenn の上限の70字に収めるため「開発者向け」を外した（68字）。Zenn の下書きにも同じ変更を入れて保存した
- 変更 `promo/zenn/macorn-intro.md` — タイトルとトピックを変える

### Macorn：Zenn の記事の画面の画像で、角が白く出るのを直す

- **きっかけ**：konta の指摘（2026-11-10）「使用している画像の角が白くなってしまっているのですが、角は透明にできないか」（Zenn の記事の話）
- **意図・方針**：画面の画像（`site/assets/screens/`）は、窓の丸い角の外がすでに透明になっている。Zenn ではその透明な部分の後ろが白く塗られて見える。Zenn の表示は変えられないので、記事用に、紺の背景（LP の SNS 用画像と同じ色の重なり）に窓と影を載せた、透明な部分のない画像を別に作った。どんな背景の上でも同じに見える。LP の画像は、角を透明にしたまま変えない
- 変更 `promo/build-site-assets.sh` — 記事用の画面の画像（`site/assets/article/screens/`）も作る
- 追加 `site/assets/article/screens/` — 記事用の画面の画像7枚（1600×952、透明な部分なし）
- 変更 `promo/zenn/macorn-intro.md` — 画面の画像を記事用のものに差し替える

### Macorn：Zenn の記事に、サブフォルダも探す絞り込みを書き足す

- **きっかけ**：konta の依頼（2026-11-10）「書き足して」（0.3.24 で絞り込みがサブフォルダの中も探せるようになり、記事にまだ書いていなかったのを受けて）
- **意図・方針**：「主な機能」の最後に「8. 絞り込み：サブフォルダの中まで、名前で探す」を足した。使い方（⌘F・`/`、⌥⌘F）、場所の表示、「含まれているフォルダを開く」、探さない場所・打ち切り・自動更新を短くまとめ、`find . -name` の代わりになることを添えた。LP に画面の画像がないので、画像は足していない。Zenn の下書きにも同じ変更を入れて下書き保存し、開き直して原稿と一字一句同じことを確かめた（公開はしていない）
- 変更 `promo/zenn/macorn-intro.md` — 絞り込みの節を足し、「そのほかの機能」の表の絞り込みの行に ⌥⌘F を足す

### Macorn：バージョン 0.3.24 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-10）「公開まで進めて」（絞り込みでサブフォルダの中も探せるようにしたのを受けて）
- **意図・方針**：0.3.23 → 0.3.24（ビルド番号は 26 → 27）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json`・`sitemap.xml` の更新日をまとめて差し替えた。リリースノートのいちばん上に 0.3.24 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — 版を 0.3.24（ビルド 27）にする
- 変更 `site/download/Macorn.dmg`・`site/index.html`・`site/version.json`・`site/sitemap.xml` — 0.3.24 に差し替え、更新日を直す（release.sh が書く）
- 変更 `site/releases/index.html` — 0.3.24 のリリースノートを足し、「最新」を付け替える

### Macorn：絞り込みで、サブフォルダの中も探せるようにする

- **きっかけ**：konta の依頼（2026-11-09）「開いているフォルダ内の検索機能が不十分なので実装して欲しい」→ どこを強化するかの確認に「サブフォルダを含む検索もオプションとしてできるようにして欲しい」
- **意図・方針**：これまでの絞り込み（⌘F・`/`）は表示中のフォルダの直下だけを名前で絞っていた。入力欄に「サブフォルダも」の切り替え（⌥⌘F・メニュー・コマンドパレット）を足し、オンなら裏でサブフォルダをたどって名前の合う項目を一覧に出す。名前の後ろに表示中のフォルダからの場所を添える。オフのときはこれまでどおり。選んだ方は設定として覚える。外部ライブラリなしの前提に合わせ、Spotlight（S-06）ではなく自前でたどる
  - 一致の基準は直下の絞り込みと同じ（大文字・小文字、濁点、全角・半角を区別しない）
  - node_modules・.git・.build・DerivedData などは中をたどらない。ホームのライブラリ・.app などのパッケージの中もたどらない。1000 件か 30 万項目で打ち切り、「件以上」と出す
  - 外での変更（削除・名前の変更など）は探し直して反映し、選択は保つ。探さない場所の中の変更では探し直さない。探し直しは前回かかった時間の倍（0.3〜30 秒）待ってから行う。ホームのように大きくて変更の多いフォルダで、ずっと探し続けないため
  - 結果の項目やタグの一覧の項目から、その場所へ移れるよう、右クリックに「含まれているフォルダを開く」を足した
  - あわせて、並べ替えを変えたときに絞り込んだ一覧が並べ直されていなかったのを直した
- 追加 `Macorn/Model/SubfolderSearch.swift` — サブフォルダをたどって名前で探す・取り消し・変更の判定・場所の相対パス
- 変更 `Macorn/Browser/FileBrowserViewController+Keyboard.swift` — 絞り込みを、直下だけとサブフォルダまでの2通りにする。探し直し・取り消し
- 変更 `Macorn/Browser/FileBrowserViewController.swift` — 検索の状態を持つ。外での変更・並べ替えを結果に反映する。結果の行に場所を添える。右クリックに「含まれているフォルダを開く」
- 変更 `Macorn/Browser/FilterBarView.swift` — 「サブフォルダも」の切り替え・探している最中の表示・件数
- 変更 `Macorn/Browser/FileCellView.swift` — 場所を、表示中のフォルダからの相対パスで出せるようにする
- 変更 `Macorn/Browser/PaneState.swift`・`Macorn/Model/Preferences.swift` — 「サブフォルダも」の状態と、その設定
- 変更 `Macorn/Browser/StatusBarView.swift` — 結果の件数を「n 件（サブフォルダも含めて絞り込み中）」と出す
- 変更 `Macorn/Model/FileNode.swift` — 自分の中身にせずに子の項目を作る処理を分ける
- 変更 `Macorn/App/MainMenu.swift`・`Macorn/Palette/CommandCatalog.swift`・`Macorn/Browser/FileBrowserViewController+Files.swift` — 編集 › 絞り込みでサブフォルダも探す（⌥⌘F）と、パレットでの英語の呼び名・チェックの表示
- 変更 `Macorn/App/DebugAutomation.swift` — 自動操作の手順 `subfolders`・`results`・`enclosing` を足し、`filter` で入力欄も開くようにする
- 追加 `MacornTests/SubfolderSearchTests.swift` — サブフォルダの検索のテスト
- 変更 `docs/REQUIREMENTS.md` — S-04 とキー操作の表に、サブフォルダも探す絞り込みを足す

## 2026-11-09

### Macorn：バージョン 0.3.23 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-09）「公開まで進めて」（一覧の並べ替えが起動のたびに名前順へ戻る不具合を直したのを受けて）
- **意図・方針**：0.3.22 → 0.3.23（ビルド番号は 25 → 26）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。リリースノートのいちばん上に 0.3.23 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — 版を 0.3.23（ビルド 26）にする
- 変更 `site/download/Macorn.dmg`・`site/index.html`・`site/version.json`・`site/sitemap.xml` — 0.3.23 に差し替え、更新日を直す（release.sh が書く）
- 変更 `site/releases/index.html` — 0.3.23 のリリースノートを足し、「最新」を付け替える

### Macorn：一覧の並べ替えが、起動のたびに名前順へ戻る不具合を直す

- **きっかけ**：konta の報告（2026-11-09）「アプリを開いた際に最初に名前順でソートされている。過去に自分がソートした順番に設定しておくことはできないのか。毎回、変えるのが面倒」→ 確認の質問に「起動するたびに戻る」
- **意図・方針**：並べ替えはもともと設定（`sortKey`・`sortAscending`）に保存していた。ところが一覧が列の幅などを保存・復元する仕組み（`autosaveName`）が、復元のときに AppKit 側に残っていた古い並べ替えも戻してきて、その知らせで設定を書き換えていた。前回のタブをいくつも開き直す起動で、名前順に上書きされていた（自動操作は前回のウィンドウを開かないので、これまでの確認では出なかった）。並べ替えは設定を正とし、復元の間の知らせは無視して最後に設定の並べ替えを当て直すようにした。フォルダごとに並べ替えを覚える形にはしていない（全体で1つのまま）
- 変更 `Macorn/Browser/FileBrowserViewController.swift` — 列の復元の間は並べ替えの知らせを無視する
- 変更 `Macorn/App/AppDelegate.swift` — `MACORN_DEBUG_RESTORE` を指定した自動操作では、前回のウィンドウ・タブを開き直す（保存はしない）
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `order`（各ウィンドウの一覧の先頭の並びと、見出し・設定の並べ替え）を足す
- 変更 `README.md` — `MACORN_DEBUG_RESTORE` を環境変数の表に足す

### Macorn：Zenn の記事を 0.3.22 のアプリに合わせる

- **きっかけ**：konta の依頼（2026-11-09）「zenn の記事のドラフトも全体的に更新しておいてほしい」
- **意図・方針**：記事は 0.3.11 のころの内容で、そのあとに入った内蔵ターミナル・Git のブランチ名と GitHub への導線・ファイルごとの差分・プレビューでの Markdown／テキストの編集・Word のプレビュー・プレビューの最大化・ボタンの置き場所の変更が抜けていた。「ターミナル・エディタ・Git 連携」の節を「内蔵ターミナル」と「Git・GitHub」の2つに分け、プレビューの節は「読んで、その場で直す」にした。キーはメニューの定義（`Macorn/App/MainMenu.swift`）と照らし合わせた。LP の画面写真は 2026-11-07 に同じ名前のまま撮り直したので、Zenn が前の画像を覚えていないよう、画像の URL に `?v=2` を付けた。Zenn の下書き（https://zenn.dev/konta8420/articles/da5fc2b984e901 ）は画像の URL がまだ macorn.vercel.app のころのものだったので、本文を原稿とまるごと入れ替えて下書き保存し、原稿と一字一句同じこと・画像 11 枚と表 4 つが表示されることを確かめた（公開はしていない）
- 変更 `promo/zenn/macorn-intro.md` — 上の機能を書き足し、節を組み直す。そのほかの機能の表に `⌥⌘P` を足し、新規フォルダ・新規ファイルのボタンの場所を「パスバーの右」に直す

## 2026-11-07

### Macorn：LP の紹介動画と画面を、最新の機能に合わせて作り直す

- **きっかけ**：konta の依頼（2026-11-07）「ここまでの機能を反映させてデモ動画を作成して欲しい」→「LT 用ではなく、LP 用に最新のアップデートをしたデモ動画を」
- **意図・方針**：LP の紹介動画（約 72 秒）は 10 月末の画面のままで、そのあとに足したセクション・プレビューでの編集・パスで開く・内蔵ターミナル・Git の差分が入っていなかった。作り方（紙芝居形式・字幕のみ・固定視点）はそのままに、撮影し直して場面を 8 つ（タグ・セクション・プレビューで直す・パスで開く・2画面・コマンドパレット・内蔵ターミナル・Git の差分）に組み直した（約 89 秒）。差分のウィンドウは半透明の部分に後ろの一覧が透けるので、ウィンドウだけを撮って一覧の画面に重ねる。内蔵ターミナルには利用者名とマシン名が写るので、撮影のときだけ短いプロンプトにする。LP の画面（機能の節・SNS 用の画像）も同じ撮影で新しくした
- 変更 `promo/capture/steps.txt` — セクション・プレビューでの書き足し・パスの入力・内蔵ターミナル・差分のウィンドウの撮影を足す。使わなくなった場面（ファイルの検索・画像のプレビュー）は撮らない
- 変更 `promo/capture/capture.py` — 手順の中の `{HERE}` をこのフォルダに置き換える。撮影のときだけ内蔵ターミナルを短いプロンプトにする。アプリが撮ったウィンドウの画像（`*_window.png`）も書き出す
- 追加 `promo/capture/md-edit.js` — README のプレビューで、チェックリストと太字を書き足す（撮影用）
- 追加 `promo/capture/compose.py` — 一覧の画面に差分のウィンドウを重ねて `gitdiff.png` を作る
- 変更 `promo/sample/make-sample.sh` — 差分で見せるため、acorn-web の `AcornList.tsx` に行の追加と削除のある変更を入れておく
- 変更 `promo/video/src/Flow.tsx`・`promo/video/README.md` — 場面を 8 つに組み直す。締めに macorn.app を出す
- 変更 `promo/video/public/flow/` — 撮り直した画面に差し替える（`gitdiff`・`pathinput`・`pathopened`・`preview_edit`・`terminal` を追加、`palette_file`・`preview_image` を削除）
- 変更 `site/assets/macorn-promo.mp4`・`site/assets/video-poster.jpg`・`site/assets/og.png`・`site/assets/screens/*.webp` — 新しい動画と画面に差し替える（`promo/build-site-assets.sh` で作る）
- 変更 `site/index.html` — 動画の節の説明を新しい中身に合わせる。2画面とコマンドパレットの画像の説明（alt）を、撮り直した画面に合わせて直す

## 2026-11-06

### Macorn：バージョン 0.3.22 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-06）「コミットして公開」（テキスト（.txt）をプレビューのまま編集できるようにしたのを受けて）
- **意図・方針**：0.3.21 → 0.3.22（ビルド番号は 24 → 25）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。リリースノートのいちばん上に 0.3.22 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — 版を 0.3.22（ビルド 25）にする
- 変更 `site/download/Macorn.dmg`・`site/index.html`・`site/version.json` — 0.3.22 に差し替える（release.sh が書く）
- 変更 `site/releases/index.html` — 0.3.22 のリリースノートを足し、「最新」を付け替える

### Macorn：テキスト（.txt）もプレビューのまま編集できるようにする

- **きっかけ**：konta の依頼（2026-11-06）「txt も md と同じようにプレビューと編集ができるようにして欲しいです」
- **意図・方針**：それまで .txt はプレビューの対象外だった。Markdown と同じ Web の領域・保存の仕組み（手を止めて 0.4 秒ほどで自動保存、ほかのファイルへ移る前にも保存、自分の保存では表示し直さない、ファイルを置き換えず中身だけ書く、UTF-8 で読めないものは編集しない、CRLF を保つ、⌘⌫ などファイル操作のキーを文字の編集に使う）に載せた。テキストは Markdown として整形すると、保存したときに「*」などが書き換わってしまうので、整形はせず書いてあるとおりの改行・空白で見せ、書いたとおりに保存する（`contenteditable="plaintext-only"`。Enter は段落ではなく改行の文字で入れ、Tab はタブを入れる）。対象は .txt と .text。既定のアプリにする種類には足していない
- 変更 `Macorn/Preview/FilePreviewController.swift` — 種類 `text` を足し、テキストを編集できる形で表示する
- 変更 `Macorn/Preview/MarkdownEditor.swift` — テキスト用の編集（書いたとおりに読み出して保存する）と見た目を足す
- 変更 `MacornTests/MarkdownRendererTests.swift` — .txt をテキストとして扱うことを確かめる
- 変更 `AGENTS.md`・`docs/REQUIREMENTS.md`・`README.md` — テキストのプレビューと編集を書き足す

### Macorn：バージョン 0.3.21 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-06）「Commit and publish」（Markdown をプレビューのまま編集できるようにしたのを、手で試したあとに）
- **意図・方針**：0.3.20 → 0.3.21（ビルド番号は 23 → 24）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。リリースノートのいちばん上に 0.3.21 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — 版を 0.3.21（ビルド 24）にする
- 変更 `site/download/Macorn.dmg`・`site/index.html`・`site/version.json` — 0.3.21 に差し替える（release.sh が書く）
- 変更 `site/releases/index.html` — 0.3.21 のリリースノートを足し、「最新」を付け替える

## 2026-11-05

### Macorn：Markdown をプレビューのまま、Notion のように編集できるようにする

- **きっかけ**：konta の依頼（2026-11-05）「md ファイルに関しては、プレビューから直接文字を修正できるようにしたいです。（Notion のように md 記法も使えるようにして欲しいです。）」
- **意図・方針**：プレビューの Web の領域をそのまま書き換えられるようにした（外部ライブラリなし）。Notion と同じく、行の頭で「# 」「## 」「- 」「1. 」「> 」「[] 」を打つ・「```」「---」で Enter を押すと見出し・リスト・引用・チェックリスト・コード・水平線に変わり、`**太字**` `*斜体*` `~~打ち消し~~` `` `コード` `` `[文字](URL)` `![説明](画像)` は閉じた時点で見た目に変わる（全角の「＃　」なども）。行の頭の ⌫ で見出しなどを段落に戻し、空の項目の Enter でリストを抜け、Tab で字下げする。保存は手を止めて 0.4 秒ほどで自動で行い、ほかのファイルへ移る前にも保存する。ファイル全体を HTML から作り直すと書き方（空行・記号の選び方など）が崩れるので、元の文章をブロックごとに覚えておき、書き換えたブロックだけを Markdown に戻すようにした。保存はファイルを置き換えずに中身だけを書く（タグが追いかけるファイルの同一性を保つ）。自分の保存では表示し直さず、カーソルを保つ。front matter は編集しない。HTML のまま書かれた部分はダブルクリックで元の文章を直す
  - スクリプトを止めたページで動かすため、編集用のスクリプトはアプリ専用の WKContentWorld で動かす（ファイルに書かれたスクリプトは止めたまま）。データは `<script>` の要素が消えるので `<meta>` の属性で渡す
  - 編集中に ⌘⌫ を押すと、メニューの「ゴミ箱に入れる」が選んでいるファイルに効いてしまう。編集中の Web の領域では、ファイル操作に割り当てたキー（⌘⌫・⌥⌘⌫・⌘D・⌘Y・⌘O・⌘I・⌘B・⌥⌘V・F5・F6）をメニューより先に受け取り、文字の編集に使う
  - ⌘Z は、Web の領域にいる間は文字の編集の取り消しにする（ファイル操作の取り消しと分ける。WebKit はウィンドウの取り消しに編集を積むので、専用のものを返す）
- 追加 `Macorn/Preview/MarkdownEditor.swift` — 編集用のスクリプトと見た目、ファイル操作のキーを受け取る Web の領域（`PreviewWebView`）
- 変更 `Macorn/Preview/MarkdownRenderer.swift` — 一番外側のブロックごとに元の行の範囲を記録し、ブロックを包んだ HTML と元の文章の切れ目を返す `renderEditable` を足す
- 変更 `Macorn/Preview/FilePreviewController.swift` — Markdown を編集できる形で表示し、スクリプトからの保存・リンクを受ける。自分の保存では表示し直さない。ほかのファイルへ移る前に保存させる
- 変更 `Macorn/Window/BrowserWindowController.swift` — Web の領域で編集している間の取り消しを分ける
- 変更 `Macorn/App/DebugAutomation.swift` — `mdjs`（編集用のスクリプトの場所で JavaScript を動かす。「;」を含むときはファイルのパス）を足す
- 追加 `MacornTests/MarkdownEditableTests.swift` — ブロックに分けても元の文章に戻ること、表示が変わらないことを確かめる
- 変更 `AGENTS.md`・`docs/REQUIREMENTS.md`・`README.md` — プレビューでの Markdown の編集を書き足す

### Macorn：バージョン 0.3.20 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-05）「コミットして公開」（Word の書類のプレビューを幅に合わせて折り返すようにしたのを受けて）
- **意図・方針**：0.3.19 → 0.3.20（ビルド番号は 22 → 23）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。リリースノートのいちばん上に 0.3.20 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — 版を 0.3.20（ビルド 23）にする
- 変更 `site/download/Macorn.dmg`・`site/index.html`・`site/version.json` — 0.3.20 に差し替える（release.sh が書く）
- 変更 `site/releases/index.html` — 0.3.20 のリリースノートを足し、「最新」を付け替える

### Macorn：Word の書類のプレビューを、幅に合わせて折り返す

- **きっかけ**：konta の報告（2026-11-05）「word で開いたものに関して、幅をうまく変えられません」
- **意図・方針**：Word の書類（.docx・.doc）はクイックルック（QLPreviewView）で見せていた。クイックルックは書類をページの幅を決め打ち（600pt ほど）にした HTML にして表示するため、プレビューを狭めると行の右が切れ、広げても余白が増えるだけで、拡大・縮小もできなかった。変換は同じもの（macOS の `qlmanage`。見出し・表・画像はクイックルックと同じ見た目）を使い、ページの幅の決め打ちだけを外して、Markdown と同じ Web の領域に出すようにした。プレビューの幅で折り返し、画像・表ははみ出させず、⌘+ / ⌘− で拡大・縮小でき、保存すると表示し直す。変換できないときはこれまでどおりクイックルックで見せる。Excel・PowerPoint・Pages などはクイックルックのまま（ページ・シートの形が意味を持つため）
- 追加 `Macorn/Preview/WordRenderer.swift` — Word の書類を `qlmanage -p -o` で HTML にし、ページの幅を外す指定を足す
- 変更 `Macorn/Preview/FilePreviewController.swift` — Word の書類は Web の領域で表示し（表示の種類 `document`）、拡大・縮小と保存時の表示し直しを効かせる。作業場所はプレビューを閉じたら消す
- 追加 `MacornTests/WordRendererTests.swift` — Word の書類の見分けと、幅の指定の足し方、実際の .docx の変換を確かめる
- 変更 `Macorn/App/DebugAutomation.swift` — `front`（キーにせず手前に出す）と `winid`（ウィンドウ番号を出す。`screencapture -l` で撮るため）を足す
- 変更 `AGENTS.md`・`docs/REQUIREMENTS.md`・`README.md` — Word の書類のプレビューのしかたを書き足す

### Macorn：バージョン 0.3.19 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-05）「デプロイまでお願いします」（一覧を畳むと境目の線が残る不具合を直したのを受けて）
- **意図・方針**：0.3.18 → 0.3.19（ビルド番号は 21 → 22）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。リリースノートのいちばん上に 0.3.19 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — 版を 0.3.19（ビルド 22）にする
- 変更 `site/download/Macorn.dmg`・`site/index.html`・`site/version.json` — 0.3.19 に差し替える（release.sh が書く。サイトマップの更新日はすでに今日だったので変わらない）
- 変更 `site/releases/index.html` — 0.3.19 のリリースノートを足し、「最新」を付け替える

### Macorn：ボタンで一覧を畳むと、境目の線が元の位置に残る不具合を直す

- **きっかけ**：konta の報告（2026-11-05）「ドラッグアンドドロップでサイドバーを動かす分には問題ないが、ボタンを押してサイドバーを畳んだ場合は元の divider があった場所に線が残ってしまう」（PDF のプレビューで、一覧を畳んだ後に縦線が残ったスクリーンショット）
- **意図・方針**：一覧を畳むボタン・最大化は `listContainer.isHidden = true` で一覧を隠していた。この方法だと NSSplitView の境目の線（専用のレイヤー）が動かず、元の位置に残ってプレビューの上に描かれていた（自動操作で確かめると、畳んだ後も線のレイヤーが x=221 のまま）。ドラッグで畳んだときと同じく、境目を左端へ寄せて NSSplitView 自身に畳ませるように変えた（線は x=0 へ移る）。畳む・「一覧を表示」・最大化・元に戻すの4通りで線の位置を確かめた
- 変更 `Macorn/Browser/FileBrowserViewController+Preview.swift` — 一覧を畳むときは `PreviewSplitView.collapseSubview(at:)` で境目を左端へ寄せて畳む。コードから畳んでいる間だけ `canCollapseSubview` で畳めるようにする
- 変更 `Macorn/App/DebugAutomation.swift` — `splitviews`（一覧とプレビューの分割の部品と線の位置を出す）と `previewmax`（プレビューの「最大化」・「一覧を表示」を押したのと同じ）を足す

### Macorn：バージョン 0.3.18 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-05）「新しい版をだして」（ターミナルのボタンを右上へ移し、追加系のボタンをパスバーの右へ分けたのを受けて）
- **意図・方針**：0.3.17 → 0.3.18（ビルド番号は 20 → 21）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。リリースノートのいちばん上に 0.3.18 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — 版を 0.3.18（ビルド 21）にする
- 変更 `site/download/Macorn.dmg`・`site/index.html`・`site/version.json`・`site/sitemap.xml` — 0.3.18 に差し替え、サイトマップの更新日を今日にする（release.sh が書く）
- 変更 `site/releases/index.html` — 0.3.18 のリリースノートを足し、「最新」を付け替える

## 2026-11-04

### Macorn：追加系のボタンをパスバーの右へ、ウィンドウ全体のものはツールバーに分ける

- **きっかけ**：konta の依頼（2026-11-04）「ファイルやフォルダなど追加はパスの欄の右に表示して、ウィンドウ全体に影響を及ぼすターミナルなどはアプリ最上部に」
- **意図・方針**：ボタンを「どこに効くか」で分けた。表示中のフォルダへの操作（新規フォルダ・新規ファイル・お気に入り）は、ツールバーから各画面のパスバーの右（GitHub・閉じる「×」の左）へ移した。画面を分けているとき、どの画面に作るかが見た目で分かる。押した画面を操作対象にしてから実行する。ツールバーには、サイドバー・戻る/進む/上へ・画面の分割・ターミナルを残した。ツールバーの「パスをコピー」は、パスバーのパスのすぐ右に同じボタンがあるので外した（選んだ項目のパスは ⌥⌘C と右クリックで）
- 変更 `Macorn/Browser/PathBarView.swift` — パスバーの右に新規フォルダ・新規ファイル・★のボタンを足す（タグの一覧では出さない）
- 変更 `Macorn/Browser/FileBrowserViewController.swift` — パスバーのボタンの操作をつなぐ
- 変更 `Macorn/Window/BrowserWindowController.swift` — ツールバーから新規フォルダ・新規ファイル・お気に入り・パスをコピーを外す
- 変更 `Macorn/App/DebugAutomation.swift` — `toolbar` でツールバーの並びを出す
- 変更 `AGENTS.md`・`README.md`・`docs/REQUIREMENTS.md` — ボタンの置き場所の方針と操作の一覧を書き換える

### Macorn：ターミナルのボタンを右上に移す

- **きっかけ**：konta の依頼（2026-11-04）「ターミナルの表示ボタンは右上に設定して欲しい」
- **意図・方針**：前提の変更。ターミナルを出し入れするボタンを、ステータスバーの左端からツールバーの右端（ウィンドウの右上）へ移した。ほかのボタンと同じ見た目にし、出している間はアイコンを塗りつぶしにして分かるようにした。2か所にあると迷うので、ステータスバーのボタンは外した。⌃` とメニューはそのまま
- 変更 `Macorn/Window/BrowserWindowController.swift` — ツールバーの右端に「ターミナル」を足し、出し入れに合わせて見た目を変える
- 変更 `Macorn/Browser/StatusBarView.swift`・`Macorn/Browser/FileBrowserViewController.swift` — ステータスバーのターミナルのボタンを外す
- 変更 `Macorn/App/DebugAutomation.swift` — `toolbarclick` を識別子でも押せるようにし、状態を見るだけの `termstate` を足す
- 変更 `AGENTS.md`・`docs/REQUIREMENTS.md` — ボタンの場所を書き換える

### Macorn：バージョン 0.3.17 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-04）「新しい版（0.3.17）をだして」（プレビューの最大化と、一覧を畳む操作を受けて）
- **意図・方針**：0.3.16 → 0.3.17（ビルド番号は 19 → 20）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。リリースノートのいちばん上に 0.3.17 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — 版を 0.3.17（ビルド 20）にする
- 変更 `site/download/Macorn.dmg`・`site/index.html`・`site/version.json` — 0.3.17 に差し替える（release.sh が書く）
- 変更 `site/releases/index.html` — 0.3.17 のリリースノートを足し、「最新」を付け替える

### Macorn：ボタン1つで一覧を畳めるようにする

- **きっかけ**：konta の依頼（2026-11-04）「ボタン一つで一覧パネルを閉じれるようにもして欲しい」
- **意図・方針**：一覧を出しているときは、プレビューのヘッダーの左端に「一覧を畳む」ボタン（サイドバーの形のアイコン）を出す。押すと一覧だけを畳み、同じ位置が「一覧を表示」に変わるので、同じ場所を押せば戻る。サイドバー・ほかの画面まで畳む最大化（右上のボタン）とは分けた
- 変更 `Macorn/Preview/FilePreviewController.swift` — 「一覧を畳む」ボタンを足し、「一覧を表示」と入れ替えて出す
- 変更 `Macorn/Browser/FileBrowserViewController+Preview.swift` — ボタンで一覧だけを畳む
- 変更 `Macorn/App/DebugAutomation.swift` — `listcollapse` をボタンと同じ経路にする
- 変更 `AGENTS.md`・`docs/REQUIREMENTS.md` — 畳み方を書き足す

### Macorn：畳んだ一覧の戻し方を分かりやすくする

- **きっかけ**：konta の指摘（2026-11-04）「ファイルやフォルダが表示されているパネルが畳まれている時に表示し直す UX がわかりにくい」
- **意図・方針**：畳んだあとは左端の細い境目と、右上の小さなアイコンでしか戻せず、気づきにくかった。一覧を畳んでいる間（境目で畳んだときも、最大化したときも）は、プレビューのヘッダーの左端に文字つきの「一覧を表示」ボタンを出し、押せば元の並びに戻るようにした
- 変更 `Macorn/Preview/FilePreviewController.swift` — 一覧を畳んでいる間だけ「一覧を表示」ボタンを出す
- 変更 `Macorn/App/DebugAutomation.swift` — 自動操作の手順 `listcollapse` を足す
- 変更 `AGENTS.md`・`docs/REQUIREMENTS.md` — 戻し方を書き足す

### Macorn：プレビューを最大化し、一覧を畳めるようにする

- **きっかけ**：konta の依頼（2026-11-04）「プレビュー表示に関して、アプリ内で画面を最大化するボタン、左側のファイルやフォルダサイドバーがこれ以上畳めなかった。これらも畳めるような UX を」
- **意図・方針**：プレビューのヘッダーに「最大化」ボタン（⇧⌘↩、表示 › プレビューを最大化）を足した。押すと、その画面の一覧・サイドバー・ほかの画面を畳んで、プレビューをウィンドウいっぱいに広げる。もう一度押すと元に戻す。サイドバーは最大化のために畳んだときだけ開き直す（自分で畳んでいたものは開かない）。ターミナルは利用者が開いたものなので残す。あわせて、一覧とプレビューの境目を左端の近くまでドラッグするか、境目をダブルクリックすると一覧だけを畳めるようにした（境目を右へ引くか、ボタンで戻る）。AppKit は狭い画面で勝手に畳むことがあるため、畳めるのは境目を操作している間だけにした。最大化中のキー操作はプレビューに届く（↑↓ でスクロール）。プレビューを閉じる・画面を分ける・閉じる・ほかの画面へ移ると、最大化をやめる
- 変更 `Macorn/Preview/FilePreviewController.swift` — ヘッダーに最大化・元に戻すボタンを足す
- 変更 `Macorn/Browser/FileBrowserViewController.swift`・`FileBrowserViewController+Preview.swift` — 一覧を畳む・最大化の切り替え、境目のドラッグ・ダブルクリックで畳む（`PreviewSplitView`）、メニューの有効・無効
- 変更 `Macorn/Window/PaneContainerViewController.swift` — 最大化した画面以外を畳み、やめたら戻す
- 変更 `Macorn/Window/BrowserWindowController.swift` — 最大化のあいだサイドバーを畳む
- 変更 `Macorn/App/MainMenu.swift` — 表示 › プレビューを最大化（⇧⌘↩）
- 変更 `Macorn/App/DebugAutomation.swift` — 自動操作の手順 `maxstate`・`listdrag` を足す
- 変更 `AGENTS.md`・`docs/REQUIREMENTS.md` — 前提と S-05 に最大化・一覧を畳む操作を書く

### Macorn：バージョン 0.3.16 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-04）「0.3.16 で公開」（プレビューの「×」の修正と、LP の SEO 対策を受けて）
- **意図・方針**：0.3.15 → 0.3.16（ビルド番号は 18 → 19）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替え、SEO 対策をした LP と一緒に公開した。リリースノートのいちばん上に 0.3.16 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.16、`CURRENT_PROJECT_VERSION` を 19 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/sitemap.xml`、`site/version.json` — 0.3.16 の DMG・表記・最新版の情報
- 変更 `site/releases/index.html` — 0.3.16 のリリースノート

### Macorn：プレビューの「×」で、選んだときのプレビューが出なくなる不具合を直す

- **きっかけ**：konta の依頼（2026-11-04）「プレビューの表示に関して、ダブルクリックでなくてもプレビューが表示されるようにして欲しい」
- **意図・方針**：プレビューの右上の「×」が、プレビューを閉じるだけでなく「選んだら右にプレビューを出す」設定そのものをオフにしていた。そのため一度閉じると、以後はダブルクリック（Macorn の中で開く）でしかプレビューが出なかった（konta の手元の設定もオフになっていたので、既定（オン）に戻した）。「×」は今のファイルのプレビューだけを閉じ、そのファイルを選んでいる間は出さず、別のファイルを選べばまた出すようにした。出さないようにするのは ⌥⌘P と設定に任せる
- 変更 `Macorn/Browser/FileBrowserViewController+Preview.swift`・`Macorn/Browser/FileBrowserViewController.swift` — 「×」で閉じたファイルだけを覚え、設定は変えない
- 変更 `Macorn/Preview/FilePreviewController.swift` — 「×」の説明を直す
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `closepreview` を足す
- 変更 `AGENTS.md`（確定している前提）

### Macorn：LP の SEO 対策（「Finder の代わり」で見つけてもらう）

- **きっかけ**：konta の依頼（2026-11-04）「mac finder 代わり、finder 代わり などで検索したときに出るようにしたい」→「SEO 対策も講じて欲しい」
- **意図・方針**：これまでの LP はタイトルにも説明にも「Finder の代わり」という言葉がなく、その検索で出る材料がなかった。検索結果の上位は比較記事が占めるので、まずは自分のサイトで「Finder の代わり」と言い切る。トップはキャッチコピー（「フォルダはそのまま。…」）を残したまま、タイトル・説明・OGP・構造化データを「Finder の代わりに使える Mac のファイルマネージャー（無料）」の方向にし、ヒーローの上に一言を足した。Finder との比較の節とよくある質問の節も足した。さらに専用のページ `/finder-alternative/` を作り、Finder で不便なこと7つと Macorn での解決・比較表・併用のしかた・よくある質問（FAQ の構造化データつき）を載せた。Finder についての記述は事実に沿うようにした（タブ・プレビュー（⇧⌘P）・タグはあるが階層はない、など）。どのページからも互いに行けるよう、ヘッダーとフッターにリンクを置き、サイトマップに載せた。外部からのリンク集め（記事の公開・掲載依頼）と Search Console での登録申請は、konta のアカウントでの作業になるので残っている
- 変更 `site/index.html` — タイトル・説明・OGP・構造化データ、ヒーローの一言、「Finder との違い」と「よくある質問」の節、ナビとフッターのリンク
- 追加 `site/finder-alternative/index.html` — 「Finder の代わり」の専用のページ
- 変更 `site/releases/index.html` — ナビとフッターのリンク
- 変更 `site/style.css` — 比較・よくある質問・専用のページ・フッターのリンクの見た目
- 変更 `site/sitemap.xml` — 専用のページを載せる
- 変更 `AGENTS.md`（確定している前提）

### Macorn：リリースノートから具体的なアプリの名前を外す

- **きっかけ**：konta の依頼（2026-11-04）「Slack など具体の名前は出さないで欲しい」
- **意図・方針**：0.3.15 のリリースノートから具体的なアプリの名前を外し、「ほかのアプリ」とだけ書いた。CHANGELOG の同じ件の書き方もそろえた
- 変更 `site/releases/index.html` — 0.3.15 の文言

### Macorn：バージョン 0.3.15 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-04）「0.3.15 で公開」（他のアプリへドラッグしたあと次のドラッグが始まらない不具合の修正を受けて）
- **意図・方針**：0.3.14 → 0.3.15（ビルド番号は 17 → 18）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。リリースノートのいちばん上に 0.3.15 を足し、「最新」の印を付け替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.15、`CURRENT_PROJECT_VERSION` を 18 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/sitemap.xml`、`site/version.json` — 0.3.15 の DMG・表記・最新版の情報
- 変更 `site/releases/index.html` — 0.3.15 のリリースノート

### Macorn：他のアプリへドラッグしたあと、次のドラッグが始まらない不具合を直す

- **きっかけ**：konta の報告（2026-11-04）「いまだに、ドラッグアンドドロップを一回した後にほかのファイルをドラッグアンドドロップしようとすると失敗する」→「アプリ内では再発しないが、他アプリにファイルをドラッグ&ドロップで添付した場合などに再発した」
- **意図・方針**：ドラッグの各段階を記録するログを入れて手元で再現してもらい、原因を特定した。他のアプリへ落とすと、ドラッグの終わりに一覧（`FileOutlineView`）の `draggingEnded` が呼ばれる。0.3.12 で足したこの処理が、元の `NSOutlineView` が持っていない `draggingEnded` を `super` で呼んでいて、「知らない命令」の例外になっていた。そのため macOS 側のドラッグの後始末が途中で止まり、次のドラッグが「前のドラッグが終わっていない」（`Cannot start a new drag. A previous drag has not finished.`）として始められなかった。元の部品が持っているときだけ `super` を呼ぶようにした。ドラッグの始まり・受け入れ・終わりは、今後の調査用に `log` で見られるよう残した（細かい記録は外した）
- 変更 `Macorn/Browser/FileOutlineView.swift` — `draggingEnded` で、ない `super` を呼ばない
- 追加 `Macorn/Browser/DragLog.swift`、変更 `Macorn/Browser/FileBrowserViewController+Files.swift` — ドラッグの流れの記録（`log show --predicate 'subsystem == "dev.macorn.Macorn" AND category == "drag"'`）

### Macorn：LP にリリースノートのページを作る

- **きっかけ**：konta の依頼（2026-11-04、0.3.14 の公開中に）「LP において、リリースノートを作成して欲しい」
- **意図・方針**：LP に `/releases/` のページを足し、0.1.0 から 0.3.14 までの各版を新しい順に並べた。中身は CHANGELOG と各版のコミットから、利用者に見える変化だけを「新機能・改善・修正」に分けて書いた（署名や LP の作業などの裏方の話は書かない）。見た目は LP と同じ色・書体のカードにし、スマホでは印を文の頭に並べる。LP のヘッダーと入手の欄から行けるようにし、サイトマップにも載せた。これから版を出すときは、このページのいちばん上に足す（AGENTS.md の前提に書いた）
- 追加 `site/releases/index.html` — リリースノートのページ
- 変更 `site/style.css` — リリースノートの見た目
- 変更 `site/index.html` — ヘッダーと入手の欄にリリースノートへのリンク
- 変更 `site/sitemap.xml` — リリースノートのページを載せる
- 変更 `AGENTS.md` — 版を出すときにリリースノートへ足すことを前提に書く

### Macorn：バージョン 0.3.14 を LP で公開する

- **きっかけ**：konta の依頼（2026-11-04）「0.3.14 で公開」（一覧のフォルダの GitHub のリポジトリ名、右上の GitHub ボタン、押せるリポジトリ名を手元で試したうえで）
- **意図・方針**：0.3.13 → 0.3.14（ビルド番号は 16 → 17）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.14、`CURRENT_PROJECT_VERSION` を 17 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/sitemap.xml`、`site/version.json` — 0.3.14 の DMG・表記・最新版の情報

### Macorn：リポジトリ名を押すと GitHub のページへ移れるようにする

- **きっかけ**：konta の依頼（2026-11-04）「レポジトリ名はクリックしたら遷移できるようにボタンにして欲しい」
- **意図・方針**：一覧の「持ち主/リポジトリ」に薄い角丸の背景を敷いてボタンらしく見せ、そこを押したときだけリポジトリのページをブラウザで開く（名前の欄のほかの所を押したときは、これまでどおり行の選択）。マウスを乗せると指の形のカーソルになる。押せる範囲は、欄と同じ条件で文字を並べて求め、省略されて見えないときは押せない。ステータスバーのリポジトリ名もリンクのボタンにした
- 変更 `Macorn/Browser/FileCellView.swift` — 「持ち主/リポジトリ」をボタンにする（背景・カーソル・押したときの動作）
- 変更 `Macorn/Browser/StatusBarView.swift` — リポジトリ名を押すと開く
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `repolink:名前` を足す
- 変更 `docs/REQUIREMENTS.md`（T-20）・`AGENTS.md`（確定している前提）

### Macorn：一覧のフォルダにも GitHub のリポジトリを出し、GitHub のボタンを右上へ移す

- **きっかけ**：konta の依頼（2026-11-04）「フォルダ一覧においても github のレポジトリを表示して欲しい。また、GitHub のボタンが右下にあり見にくいので右上に持ってきて欲しい」（リポジトリではない `work` を開いていて、どこにリポジトリの情報があるか分からなかった）
- **意図・方針**：一覧のリポジトリのフォルダは、ブランチ名の後ろに「持ち主/リポジトリ」を添え、右クリックに「GitHub で開く」を足した。行ごとに読むので git コマンドは使わず、`.git/config` を直に読む（worktree は共通の管理フォルダの設定を読む）。GitHub のボタンはステータスバーから外し、各画面のパスバーの右端（ウィンドウの右上）へ移した。画面ごとに出るので、分けていてもどの画面のリポジトリか分かる。狭い画面では「GitHub」だけにして、パスの末尾とコピーのボタンが隠れないようにした（幅が変わったらパスを末尾が見える位置に戻す）。ステータスバーのリポジトリ名・ブランチ・変更の数はそのまま
- 変更 `Macorn/Integration/GitRepository.swift`・`Macorn/Model/FileEntry.swift` — フォルダの `.git/config` からリモートを読み、項目に Web の URL を持たせる
- 変更 `Macorn/Browser/FileCellView.swift`・`Macorn/Browser/FileBrowserViewController.swift`・`Macorn/Browser/FileBrowserViewController+Integration.swift` — 一覧に「持ち主/リポジトリ」、右クリックの「GitHub で開く」
- 変更 `Macorn/Browser/PathBarView.swift`・`Macorn/Browser/StatusBarView.swift` — GitHub のボタンをパスバーの右端へ移す
- 変更 `MacornTests/GitDiffTests.swift` — `.git/config` の読み取りのテスト
- 変更 `docs/REQUIREMENTS.md`（T-20）・`AGENTS.md`（確定している前提）

## 2026-11-03

### Macorn：ステータスバーに GitHub のリポジトリ名とリンクのボタンを出す

- **きっかけ**：konta の依頼（2026-11-03）「github のレポジトリのリンクなども表示しておいて欲しい（ボタンを設ければ十分）。現状ブランチ名しか書かれていないので、レポジトリの情報が見えない」
- **意図・方針**：ステータスバーのリポジトリ名はフォルダ名だけで、どのリポジトリか分からなかった。リモート（origin。なければ最初のリモート）の URL を読み、リポジトリ名を「持ち主/リポジトリ」にして、その右に「GitHub」ボタンを置いた（依頼どおりボタンで十分とし、URL そのものは出さない。ボタンに乗せると URL が出る）。`git@github.com:…`・`ssh://`・トークンつきの `https://` も、ブラウザで開ける形に直す（トークンは捨てる）。GitLab・Bitbucket などはその名前のボタンにする。ファイル › リポジトリを Web で開く・パレットからも開ける
- 変更 `Macorn/Integration/GitRepository.swift` — リモートの URL を読み、Web の URL・リポジトリ名・サービス名にする
- 変更 `Macorn/Browser/StatusBarView.swift`・`Macorn/Browser/PaneState.swift`・`Macorn/Browser/FileBrowserViewController.swift`・`Macorn/Browser/FileBrowserViewController+Integration.swift` — ステータスバーのリポジトリ名と「GitHub」ボタン、リポジトリを Web で開く操作
- 変更 `Macorn/App/MainMenu.swift`・`Macorn/Palette/CommandCatalog.swift` — ファイル › リポジトリを Web で開く
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `gitinfo` を足す
- 変更 `MacornTests/GitDiffTests.swift` — リモートの URL の変換とリポジトリ名のテスト
- 変更 `docs/REQUIREMENTS.md`（T-20）・`AGENTS.md`（確定している前提）

### Macorn：バージョン 0.3.13 を LP で公開する

- **きっかけ**：konta の依頼「0.3.13 で公開」（内蔵ターミナル、Git リポジトリの表示とファイルごとの差分、一覧とプレビューの区切り線の修正を手元で試し「特にないです」を受けて）
- **意図・方針**：0.3.12 → 0.3.13（ビルド番号は 15 → 16）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.13、`CURRENT_PROJECT_VERSION` を 16 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.13 の DMG・表記・最新版の情報

### Macorn：内蔵ターミナルを下・左・右のどこにでも置けるようにする

- **きっかけ**：konta の依頼（2026-11-03）「ターミナルを開く位置は左右下に柔軟に移動できるようにして欲しい」
- **意図・方針**：画面とターミナルの分割の向きと順番を、置き場所に合わせて組み替える。動いているシェルはそのまま使い続ける。切り替えは、ターミナルのヘッダーの置き場所のボタン（下・左・右のメニュー）と、表示 › ターミナルの位置（パレットからも呼べる）。選んだ場所は設定として覚えるが、開いているかどうかは覚えない（起動時はいつも閉じる、の前の依頼に合わせる）。左・右に置くとウィンドウの上端まで伸びてツールバーにヘッダーが隠れたので、ヘッダーはツールバーの下から始める
- 変更 `Macorn/Terminal/TerminalPanelController.swift` — 置き場所（`TerminalPosition`）、ヘッダーの置き場所のボタン、置き場所に合わせた分割の組み替え
- 変更 `Macorn/Model/Preferences.swift` — ターミナルの置き場所を覚える
- 変更 `Macorn/Window/BrowserWindowController.swift`・`Macorn/App/MainMenu.swift`・`Macorn/Palette/CommandCatalog.swift` — 表示 › ターミナルの位置（下・左・右）
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `termpos:bottom|left|right` を足す
- 変更 `docs/REQUIREMENTS.md`（T-30）・`AGENTS.md`（確定している前提）

### Macorn：ステータスバーのボタンで内蔵ターミナルを出し入れできるようにする

- **きっかけ**：konta の依頼（2026-11-03、手元で試して）「下部の方のボタンを押して下に表示されるようにして欲しい」
- **意図・方針**：⌃` を知らなくても使えるよう、各画面のステータスバーの左端に「ターミナル」ボタンを置いた。出しているときはアクセントの色で塗る。⌃` は「出ていてフォーカスがなければターミナルへ移る」動きだが、ボタンは押すたびに出す・隠すを切り替える（ボタンとして素直な動きにするため）
- 変更 `Macorn/Browser/StatusBarView.swift`・`Macorn/Browser/PaneState.swift`・`Macorn/Browser/FileBrowserViewController.swift` — ステータスバーのターミナルのボタン
- 変更 `Macorn/Window/BrowserWindowController.swift` — ボタン用の出し入れ（`toggleTerminalPanel`）と、ボタンの見た目を出しているかどうかに合わせる
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `termbutton`・`termkey:文字`（キーボードと同じ経路で打つ）を足す。`termdump` に表示・起動の状態を出す
- 変更 `docs/REQUIREMENTS.md`（T-30）・`AGENTS.md`（確定している前提）

### Macorn：内蔵ターミナルに打ち込めないのを直し、起動時はしまっておく

- **きっかけ**：konta の指摘（2026-11-03、手元で試して）「ターミナルに打ち込めないのと、ターミナルはデフォルトではしまっておいて欲しい」
- **意図・方針**：ターミナルの開閉を分割の自動保存で覚えていたため、確認の自動操作で開いた状態が普段の設定に残り、起動時にパネルだけが開いていた。シェルは ⌃` で開いたときにしか起動しないので、開いて見えていても打ち込み先がなかった。開閉は覚えず起動時はいつも閉じておき、どんな開き方でも（区切り線を引き出したときも）パネルが出てきたらシェルを起動するようにした
- 変更 `Macorn/Terminal/TerminalPanelController.swift` — 分割の自動保存をやめる。パネルが出てきたらシェルを起動する
- 変更 `Macorn/Window/BrowserWindowController.swift` — シェルを起動するフォルダ（表示中のフォルダ）を渡す

### Macorn：ウィンドウの下に出す内蔵ターミナルを自前で作る（最初の版）

- **きっかけ**：konta の依頼（2026-11-03）「アプリの下の方で ghostty を開くこともできるようにして欲しい」→ libghostty と自前を比べたうえで「自前の内蔵ターミナルの実装は可能なのか」「お願いします」
- **意図・方針**：Ghostty の画面は macOS の制約でほかのアプリに埋め込めない。libghostty は正式な API がなく、「外部ライブラリなし」の前提も変えることになるので、自前で作った（要件 T-30 の最初の版）。目標は「ファイル操作の流れで、すぐ下でコマンドを打てる」ことで、Ghostty ほどの速さや再現度は目指さない。疑似端末（`forkpty`）でログインシェルを動かし、xterm 互換の主な命令を自前で読む。日本語で使う前提なので、全角を 2 マスで扱い、結合文字・日本語入力（変換中の表示）にも対応した。Macorn で開いたフォルダへの自動の `cd` は、コマンドの実行中や打ちかけの入力があるときは送らない（邪魔をしないため）。アプリから起動すると LANG が無く日本語が化けることがあるので、無ければ ja_JP.UTF-8 を渡す。macOS 14 から自分の枠の外にも描けてしまうため、端末の画面は枠で切る（上のヘッダーが塗りつぶされていた）。マウス操作の受け渡しと、フォント・配色の設定は次の版に回す
- 追加 `Macorn/Terminal/TerminalProcess.swift` — 疑似端末でシェルを動かし、入出力・大きさの通知・前面のプロセスの確認を行う
- 追加 `Macorn/Terminal/TerminalEmulator.swift` — 制御文字の読み取りと、画面の中身（升目・流れた行・別画面・カーソル）
- 追加 `Macorn/Terminal/TerminalView.swift` — 描画・キー入力・日本語入力・選択とコピー・貼り付け・スクロール・ファイルのドロップ
- 追加 `Macorn/Terminal/TerminalPanelController.swift` — ウィンドウの下のパネル（ヘッダーに今のフォルダと閉じるボタン）と、画面とターミナルの上下の分割
- 変更 `Macorn/Window/BrowserWindowController.swift`・`Macorn/App/MainMenu.swift`・`Macorn/Palette/CommandCatalog.swift` — 表示 › ターミナル（⌃`）、フォルダを移ったら追いかける、ウィンドウを閉じたらシェルを終える
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `terminal`・`termtype:文字`・`termdump`・`termhide` を足す
- 追加 `MacornTests/TerminalEmulatorTests.swift` — 文字・折り返し・カーソル移動・消去・色・全角・結合文字・UTF-8 の分割・別画面・スクロール範囲・挿入と削除・問い合わせ・題名とフォルダ・大きさの変更
- 変更 `docs/REQUIREMENTS.md`（T-30）・`AGENTS.md`（確定している前提）・`README.md`（フォルダの役割）

### Macorn：Git リポジトリのフォルダにブランチ名を出し、変更のあるファイルからその差分を開けるようにする

- **きっかけ**：konta の依頼（2026-11-03）「git で管理されているフォルダに関しては、それがわかるようにして欲しい。どのブランチにいるのか、リポジトリ名がなんなのか表示して欲しい」「差分があるファイルに関しては、その差分も見れるような機能を実装して欲しい」
- **意図・方針**：これまではリポジトリの中に入ったときだけ、ステータスバーにブランチ名が出ていた。一覧のどのフォルダがリポジトリかは分からなかった。一覧ではフォルダ名の後ろに「⎇ ブランチ名」をアクセントの色で添え、パスバーではリポジトリのルートの階層にブランチ名の札を付け、ステータスバーにはリポジトリ名も出す。一覧のフォルダごとに git を起動すると重いので、`.git/HEAD` を直接読む（worktree・submodule の `.git` ファイルにも対応）。差分は 2026-11-01 に作った差分のウィンドウ（ユーザーの選択で「専用のウィンドウ」）を、そのファイルを選んだ状態で開く。フォルダならその中の最初の変更を選ぶ
- 変更 `Macorn/Integration/GitRepository.swift` — `.git/HEAD` からブランチ名を読む（`headBranch(ofRepositoryAt:)`）
- 変更 `Macorn/Model/FileEntry.swift` — リポジトリのフォルダならブランチ名を持つ
- 変更 `Macorn/Browser/FileCellView.swift` — フォルダ名の後ろにブランチ名を添える。Git の印を押せるようにする
- 変更 `Macorn/Browser/PathBarView.swift`・`Macorn/Browser/StatusBarView.swift`・`Macorn/Browser/PaneState.swift` — パスバーのリポジトリのルートにブランチ名の札、ステータスバーにリポジトリ名
- 変更 `Macorn/Browser/FileBrowserViewController.swift`・`Macorn/Browser/FileBrowserViewController+Integration.swift`・`Macorn/App/MainMenu.swift`・`Macorn/Palette/CommandCatalog.swift` — 右クリックの「差分を見る」、印のクリック、ファイル › 選んだ項目の差分を見る
- 変更 `Macorn/Window/ChangesWindow.swift` — 開くときに選ぶファイルを渡せるようにする
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `filediff` を足す
- 変更 `MacornTests/GitDiffTests.swift` — HEAD の読み取りとリポジトリのフォルダの見分けのテスト
- 変更 `docs/REQUIREMENTS.md`（T-20・T-23）・`AGENTS.md`（確定している前提）

### Macorn：一覧とプレビューの区切り線を、一覧の右の余白からも掴めるようにする

- **きっかけ**：konta の指摘（2026-11-03、0.3.12 の画面のスクリーンショットつき）「ファイル一覧とプレビューの divider も選択しにくい」
- **意図・方針**：区切り線の両側 4 ポイントは掴めるようになっていたが、一覧には右に 10 ポイントの余白（`listInset`）があり、見た目の境目は行が終わってから線までの帯になっていた。その帯を押しても反応しなかったので、一覧側は余白ごと（10 ＋ 2 ポイント）掴めるようにした。プレビュー側は 4 ポイントのまま（プレビューの操作を邪魔しないように）
- 変更 `Macorn/Window/DividerGrab.swift` — 線の左右（上下）で別々に掴める幅を足せるようにする
- 変更 `Macorn/Browser/FileBrowserViewController+Preview.swift` — 一覧とプレビューの区切り線は、一覧側の余白も掴めるようにする
- 変更 `Macorn/App/DebugAutomation.swift` — `dividerhit` で測る範囲を -14〜+6 ポイントに広げる

### Macorn：バージョン 0.3.12 を LP で公開する

- **きっかけ**：konta の依頼「0.3.12 で公開」（区切り線を掴みやすくしたことと、ドラッグ＆ドロップが1回で効かなくなる不具合の修正を受けて）
- **意図・方針**：0.3.11 → 0.3.12（ビルド番号は 14 → 15）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.12、`CURRENT_PROJECT_VERSION` を 15 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.12 の DMG・表記・最新版の情報

### Macorn：区切り線を掴みやすくし、ドラッグ＆ドロップが1回で効かなくなるのを直す

- **きっかけ**：konta の依頼（2026-11-03）「サイドバーなどの幅を変えるときにうまく divider を選択できない」「一度ファイルをドラッグアンドドロップで操作した後にほかのファイルがドラッグアンドドロップできない事象が発生する」
- **意図・方針**：区切り線は 1 ポイントの細い線（`.thin`）で、掴める範囲も線の幅しかなかった。見た目は細いまま、掴める範囲を線の両側に 4 ポイントずつ広げた（サイドバー・分けた画面どうし・一覧とプレビューの3か所）。ドラッグの件は、2026-11-01 に足した「ドラッグが一覧の上にある」状態が、ドロップを受け付けなかったとき（同じフォルダの上で離したときなど）に終わりの知らせが届かず残り、以後フォルダの変化を一覧に反映しなくなっていた。移動したファイルが一覧に残り、それを掴んでも動かせなかった。マウスのボタンを離していればドラッグは終わったとみなし、後回しにした読み直しはドラッグの終わりを見張って必ず行うようにした。あわせて、ドロップで移動したときは移動元のフォルダも読み直す
- 追加 `Macorn/Window/DividerGrab.swift` — 区切り線の掴める範囲と、ウィンドウ全体の分割（`BrowserSplitViewController`）
- 変更 `Macorn/Window/BrowserWindowController.swift`・`Macorn/Window/PaneContainerViewController.swift`・`Macorn/Browser/FileBrowserViewController+Preview.swift` — 3か所の区切り線の掴める範囲を広げる
- 変更 `Macorn/Browser/FileOutlineView.swift` — 「ドラッグが一覧の上にある」は、マウスのボタンを押している間だけにする
- 変更 `Macorn/Browser/FileBrowserViewController.swift`・`Macorn/Browser/FileBrowserViewController+Files.swift` — ドラッグの終わりを見張って後回しにした読み直しを行う。ドロップで移動したら移動元のフォルダも読み直す
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `dividerhit`（区切り線の近くを押したときに反応するか）・`dragstuck`（終わりの知らせが届かなかった状態を作る）を足す

## 2026-11-02

### Macorn：Zenn の記事を 0.3.11 のアプリに合わせる

- **きっかけ**：konta の連絡（2026-11-02）「色々と修正をしたので zenn の方は公開予定を取消にしています」
- **意図・方針**：記事は 0.3.9 のころの内容で、その後に入った機能が抜けていた。公開し直す前に本文を今のアプリに合わせた。画像は差し替えていない（2画面の画像はそのまま使える）
- 変更 `promo/zenn/macorn-intro.md` — 画面を最大6画面まで自由に分けられること・分けた画面の「×」、サイドバーのサブセクション・「＋ 追加」・「…」メニュー、変更の差分のウィンドウを書き足す

## 2026-11-01

### Macorn：バージョン 0.3.11 を LP で公開する

- **きっかけ**：konta の依頼「0.3.11 で公開」（ドラッグでの移動の不具合の修正と、変更の差分を見るウィンドウを受けて）
- **意図・方針**：0.3.10 → 0.3.11（ビルド番号は 13 → 14）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.11、`CURRENT_PROJECT_VERSION` を 14 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.11 の DMG・表記・最新版の情報

### Macorn：GitHub Desktop のような、変更の差分を見るウィンドウを足す

- **きっかけ**：konta の依頼（2026-11-01）「github desktop のような差分の確認機能も実装して欲しい」。範囲と出す場所はユーザーの選択で「見るだけ」「専用のウィンドウ」
- **意図・方針**：Git の状態はステータスバーと一覧の印で分かるが、中身の違いはターミナルで見るしかなかった。GitHub Desktop の「Changes」と同じく、左に変更のあるファイル、右に行ごとの差分（追加は緑・削除は赤・前後の行番号）を並べる。比べるのは最後のコミットと今の中身で、ステージしたかどうかは分けない（見るだけなので）。未追跡のファイルは全体を追加として見せ、まだコミットがないリポジトリは空と比べる。git の出力は自前で読む（外部ライブラリなし）。大きな差分で固まらないよう、バイナリは出さず 5000 行で打ち切り、読み込みは裏で行う
- 追加 `Macorn/Integration/GitDiff.swift` — 変更の一覧（`git status -uall`）と、1ファイル分の差分（`git diff HEAD`・未追跡は `--no-index`）を読む
- 追加 `Macorn/Window/ChangesWindow.swift` — 変更のウィンドウ（リポジトリごとに1つ。前に出るたびと ⌘R で読み直す）
- 変更 `Macorn/Integration/GitRepository.swift` — git の実行で、0 以外の終了コードと UTF-8 でない出力を受け付けられるようにする
- 変更 `Macorn/Browser/StatusBarView.swift`・`Macorn/Browser/FileBrowserViewController.swift`・`Macorn/Browser/FileBrowserViewController+Integration.swift`・`Macorn/App/MainMenu.swift`・`Macorn/Palette/CommandCatalog.swift` — ステータスバーの「n 件の変更」、ファイル › 変更を見る（差分）…、パレットから開く
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `changes`・`changeselect:パス`・`changesinfo`・`snapchanges:名前`・`closechanges` を足す
- 追加 `MacornTests/GitDiffTests.swift` — 差分と変更の一覧の読み取り、実際のリポジトリでの差分
- 変更 `docs/REQUIREMENTS.md`（T-23）・`AGENTS.md`（確定している前提）・`README.md`（フォルダの役割）

### Macorn：ドラッグで移動するときに一覧が引き戻され、スクロールできなくなるのを直す

- **きっかけ**：konta の指摘（2026-11-01）「フォルダなどをドラッグして別のフォルダに移動するときに変な挙動になりページをスクロールできなくなったりして著しくUX が悪い」
- **意図・方針**：一覧を読み直すたびに選択を戻す処理が、選んだ行まで一覧をスクロールしていた。ドラッグ中は動かしている項目が選ばれているため、フォルダの自動展開や中身の変化のたびに一覧が引き戻されていた（自動操作で、下までスクロールした一覧が変化1回で先頭へ戻るのを確認）。読み直しでは表示位置を動かさないようにし、あわせてドラッグ中のずれの元を断った。ドラッグ中にフォルダの上で止まると開くのはそのままにし（konta の依頼「ドラッグ中のフォルダの展開がされなくなった」。いったん止めたのを戻した）、まだ読んでいないフォルダはその場で読んでから開いて、中身が後から入って行がずれないようにした
- 変更 `Macorn/Browser/FileBrowserViewController.swift` — 読み直しのあとの選択の戻しでスクロールしない（`select(_:scroll:)`）。ドラッグ中はフォルダの変化による読み直しを後回しにし、ドラッグ中に自動で開くフォルダは中身を読んでから開く
- 変更 `Macorn/Browser/FileBrowserViewController+Files.swift` — この一覧から始めたドラッグの状態を持ち、終わったら後回しにした読み直しを行う
- 変更 `Macorn/Browser/FileBrowserViewController+Keyboard.swift` — サイズ順の並べ直しでも表示位置を動かさない
- 変更 `Macorn/Browser/FileOutlineView.swift` — ほかの場所からのドラッグが一覧の上にあるかを持つ
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `dragstate:begin|end`・`listinfo`・`scrollbottom` を足す

### Macorn：バージョン 0.3.10 を LP で公開する

- **きっかけ**：konta の依頼「0.3.10 で公開」（セクションの「…」・サイドバーのホバー・分けた画面の「×」を受けて）
- **意図・方針**：0.3.9 → 0.3.10（ビルド番号は 12 → 13）。版の比較は数値で行う（`UpdateChecker.isNewer`）ので、0.3.9 の利用者にも新しい版として届く。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.10、`CURRENT_PROJECT_VERSION` を 13 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.10 の DMG・表記・最新版の情報

### Macorn：セクションの右に「…」を付け、サイドバーの行をホバーで光らせ、分けた画面に「×」を付ける

- **きっかけ**：konta の依頼「各セクションの右にも3点リーダーなどを設けて編集とセクションやタグの追加をできるようにして欲しい」「サイドバーのコンテンツに関してはホバー時に反応するように」「タブを閉じるためのバツボタンが現状ないので足して欲しい」
- **意図・方針**：右クリックを知らなくても、セクションごとに足す・直すができるよう、見出しとサブセクションの右に「…」を常に出し、右クリックと同じメニューにした。メニューは上に「追加」（お気に入り＝表示中のフォルダを追加、タグ＝タグを作る、タグのセクション＝下にタグを作る、自分のセクション＝タグを作ってここに置く・表示中のフォルダを置く・サブセクションを作る、どれも＝この上・この下にセクションを作る）、下に「編集」（移動・名前の変更・隠す・削除など）。サイドバーの行はマウスが乗るとうすく塗る（見出しとヒントの行は除く）。「×」はウィンドウのタブにはすでに付いているため、分けた画面（ペイン）を閉じる手段がショートカットとメニューしかないことへの依頼と受け取り、分けているときだけ各画面のパスバーの右端に出した
- 変更 `Macorn/Sidebar/SidebarViewController.swift` — 見出し・サブセクションの「…」（`SidebarMoreButton`）、追加・編集に組み直したメニュー、ホバーで塗る行（`SidebarRowView`）
- 変更 `Macorn/Sidebar/SidebarPrompts.swift` — タグを作ってそのままセクションに置けるようにする
- 変更 `Macorn/Settings/Theme.swift` — `ThemedRowView` を継承できるようにする
- 変更 `Macorn/Browser/PathBarView.swift`、`Macorn/Browser/FileBrowserViewController.swift`、`Macorn/Window/PaneContainerViewController.swift` — 分けているとき、パスバーの右端にその画面を閉じる「×」を出す
- 変更 `Macorn/App/DebugAutomation.swift` — 自動操作に `sectionmenu`・`sectionmenudo`・`sbhoverrow`・`closepanebutton` を足す
- 変更 `AGENTS.md`、`docs/REQUIREMENTS.md`（P-09・N-04） — 「…」・ホバー・画面の「×」を書く

### Macorn：LP を独自ドメイン macorn.app に移し、バージョン 0.3.9 を公開する

- **きっかけ**：konta が macorn.app を買い（Vercel のプロジェクト `macorn` に付けた）、「macorn.app で切り替える」と依頼
- **意図・方針**：アプリの版の確認先・`version.json` のダウンロード先・LP の正規の URL などを https://macorn.app にそろえた。0.3.8 までのアプリは https://macorn.vercel.app/version.json を見に行くため、旧ドメインは消さずに残す（消すと今の利用者に更新が届かない）。Vercel の設定で macorn.app が www.macorn.app へ転送されていても、アプリの確認とダウンロードは転送をたどるので動く。0.3.8 → 0.3.9（ビルド番号は 11 → 12）
- 変更 `Macorn/App/UpdateChecker.swift`、`MacornTests/UpdateCheckerTests.swift` — 版の確認先を https://macorn.app/version.json に
- 変更 `scripts/release.sh` — `version.json` に書くダウンロード先・ページを macorn.app に
- 変更 `site/index.html`、`site/robots.txt`、`site/sitemap.xml` — 正規の URL・OGP・構造化データ・サイトマップを macorn.app に
- 変更 `.github/workflows/vercel-production.yml` — 公開後の表示の URL を macorn.app に
- 変更 `promo/zenn/macorn-intro.md` — LP へのリンクと画像の URL を macorn.app に
- 変更 `AGENTS.md`、`docs/REQUIREMENTS.md`、`README.md` — LP の URL を macorn.app にし、旧ドメインを残す理由を書く
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.9、`CURRENT_PROJECT_VERSION` を 12 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.9 の DMG・表記・最新版の情報

### Macorn：バージョン 0.3.8 を LP で公開する

- **きっかけ**：konta の依頼「お願いします」（サイドバーの「＋ 追加」を上部へ移した変更を利用者に届けるため）
- **意図・方針**：0.3.7 → 0.3.8（ビルド番号は 10 → 11）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.8、`CURRENT_PROJECT_VERSION` を 11 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.8 の DMG・表記・最新版の情報

### Macorn：サイドバーの「＋ 追加」を上部へ移す

- **きっかけ**：konta の依頼「サイドバーにおいて、セクションやタグの追加のプラスボタンを上部に設けて欲しい」（0.3.7 の公開のあと）
- **意図・方針**：いちばん下だと、項目が多いときに目に入りにくい。タイトルバーのすぐ下（一覧の上）に置き、下のボタンは外して1か所にまとめた。メニューの中身は変えず、ボタンのすぐ下に開く
- 変更 `Macorn/Sidebar/SidebarViewController.swift` — 「＋ 追加」と区切り線を一覧の上に置き、メニューをボタンの下に出す
- 変更 `AGENTS.md`、`docs/REQUIREMENTS.md`（N-04）、`README.md` — 「＋ 追加」の場所を上部に直す

### Macorn：バージョン 0.3.7 を LP で公開する

- **きっかけ**：konta の依頼「0.3.7 で公開」（画面の自由な分割・サブセクション・「＋ 追加」・パスの入力の直し・タブの「×」などを受けて）
- **意図・方針**：0.3.6 → 0.3.7（ビルド番号は 9 → 10）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。0.3.5 以降の利用者は「今すぐ更新」で入れ替えられる
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.7、`CURRENT_PROJECT_VERSION` を 10 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.7 の DMG・表記・最新版の情報

### Macorn：サイドバーにサブセクションを作り、入れ子で整理できるようにする

- **きっかけ**：konta の依頼（2026-11-01）「サブセクションなどを適宜作成、整理できるようにしたい」
- **意図・方針**：サブセクションも、セクションと同じく見た目だけのまとまり（項目に何も付けない）。仕組みは「自分で作ったセクションの中に置いたセクション」にし、置き場所・タグを1か所だけに置く決まり・ドラッグの受け付けを、セクションと同じ処理でまかなう。入れ子は何段でもでき、行を押すと開く・閉じる（閉じた状態は覚える）。お気に入りの中には作らない（お気に入りはタグの一覧のため）
  - 作り方：セクション・サブセクションの右クリック「サブセクションを作る…」、または「＋ 追加」›「サブセクションを作る」
  - 整理：自分で作ったセクションを、ほかのセクションの中へドラッグするとサブセクションになる。自分の中・自分のサブセクションの中へは入れない。右クリックの「いちばん上の階層のセクションにする」か、見出しの間へのドラッグで外に出せる。削除すると中のサブセクションも消える（項目そのものは残る）
  - 「セクションに置く」のメニューには「親 › 子」の名前で、親のすぐ後ろに出す
- 変更 `Macorn/Sidebar/SidebarStore.swift` — セクションに親（`parentID`）を、項目にサブセクションを指す種類（`sectionID`）を足す。作る・入れる・外に出す・上下に動かす・削除（中ごと）を足す。保存の形に `parent` と `{"section": ID}` を足す
- 変更 `Macorn/Sidebar/SidebarViewController.swift` — サブセクションを、中身を子に持つ開閉できる行として出す。セクションのドラッグで入れ子にする。右クリックと「＋ 追加」にサブセクションの操作を足す
- 変更 `Macorn/Sidebar/SidebarPrompts.swift` — サブセクションの名前を聞くダイアログを足す。削除の確認文にサブセクションのことを書く
- 変更 `Macorn/Browser/FileBrowserViewController+Sections.swift` — 一覧の右クリック「セクションに置く」にサブセクションも出す
- 変更 `MacornTests/SidebarTests.swift` — サブセクションの作成・入れ子・保存と読み直し・外に出す・削除のテストを足す
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `mksub:親>名前` を足す

### Macorn：画面を右・下に自由に分けて、4画面なども組めるようにする

- **きっかけ**：konta の依頼（2026-11-01）「複数画面表示に関しても、単なる2画面ではなく4画面構成なども柔軟にできるようにして欲しい」。確認で「自由に分割」「（コピー先などは）直前の画面へ」を選んだ
- **意図・方針**：前提の変更（2画面だけ → 自由な分割）。iTerm2 や VS Code のように、操作中の画面を「右に分ける」（⌘⌥\）・「下に分ける」（⌘⌥⇧\）で何度でも分け、入れ子で並べる（1タブ最大6画面）。同じ向きならすぐ隣に足し、向きが違うときだけ入れ子を作る。閉じて1つになったまとまりは中身に置き換え、余計な入れ子を残さない。⌘\ はこれまでどおり（1画面なら右に分ける、分けていれば操作中の画面だけを残して1画面に戻す）。「反対側」（F5・F6・⌘⌥=・⌘⌥U）は直前に操作した画面、Tab は左上から順に次の画面。狭いウィンドウでは操作中の画面だけを見せ、広げたら元の大きさに戻す。並びと大きさはタブごとに保存し、以前の2画面の保存の形も読める
- 変更 `Macorn/Window/PaneContainerViewController.swift` — 画面の並びを入れ子のまとまり（`PaneGroupController`）で持つ形に作り直す。保存用の並び（`PaneTreeLayout`）を足す
- 変更 `Macorn/Window/BrowserWindowController.swift`・`Macorn/App/MainMenu.swift`・`Macorn/Palette/CommandCatalog.swift` — 「右に分ける」「下に分ける」「この画面を閉じる」を足し、名前を「もう一方の画面」に合わせる
- 変更 `Macorn/Palette/PaletteController.swift` — ⌘ を押して開いたら、もう一方の画面へ移る（順番で次ではなく）
- 変更 `Macorn/App/AppDelegate.swift` — 消えたフォルダの画面を除いて並びを復元する
- 追加 `MacornTests/PaneLayoutTests.swift` — 並びの保存と読み直し、以前の形式、消えたフォルダの除き方、並びからの組み立てと閉じたときのまとめ方のテスト
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `split:right|down`・`closepane`・`panelayout` を足す
- 変更 `docs/REQUIREMENTS.md`・`AGENTS.md` — 4章に P-09（自由な分割）と3画面以上での「反対側」を足し、ショートカット一覧と確定している前提を直す

### Macorn：サイドバーの下に「＋ 追加」を置き、足すものを選べるようにする

- **きっかけ**：konta の依頼（2026-11-01）「サイドバーにプラスボタンを作成して、セクション、タグの追加など柔軟に選択できるように。現状、タグのプラスボタンしかない」
- **意図・方針**：これまでの「＋ セクションを作る」ボタンを「＋ 追加」にし、押すとメニューを出す。タグを作る・セクションを作る・サブセクションを作る・表示中のフォルダをお気に入りに追加・表示中のフォルダをセクションに置く・タグをセクションとして出す・隠したセクションを表示・サイドバーをカスタマイズ、を選べる。使えないもの（すでにお気に入りなど）は灰色にする
- 変更 `Macorn/Sidebar/SidebarViewController.swift` — 「＋ 追加」のボタンとメニューを作る
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `addmenu`（中身を書き出す・項目を選ぶ）を足す
- 変更 `docs/REQUIREMENTS.md`・`AGENTS.md` — N-04 と確定している前提に書く

### Macorn：パスの入力中に、ほかの場所をクリックしたら元の表示に戻す

- **きっかけ**：konta の依頼（2026-11-01）「パスにフォーカスが当たっている状況で他の場所をクリックしても戻らない」
- **意図・方針**：これまではフォーカスが外れたときだけ入力をやめていたが、一覧の空いている所などフォーカスを取らない場所のクリックではフォーカスが外れず、入力欄のまま残っていた。入力中だけアプリ内のクリックを見張り、入力欄の外（一覧・サイドバー・ツールバー・ほかのウィンドウ）が押されたら入力を取り消してパンくずに戻す。押した先の操作（項目を選ぶなど）はそのまま行う。入力欄の中のクリックでは戻さない
- 変更 `Macorn/Browser/PathBarView.swift` — パスの入力欄に、外のクリックの見張りを足す（入力欄が消えたら見張りも外す）
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `clickwindow:横,縦`（ウィンドウの決まった位置をアプリ全体の経路で押す。`pathbar,横` でパスバーの中）を足す

### Macorn：タブにいつも見える「×」を付け、ボタンの説明を出して具体的にする

- **きっかけ**：konta の依頼（2026-11-01）「タブを複数開いた場合にタブを閉じるボタンがない」「各種ボタンにホバー時に機能の説明がでなく、何の機能なのか（何のコピーなのか）わからない」、続けて「パスのコピーボタンはパスが表示されているところの右に表示して欲しい」
- **意図・方針**：
  - タブは macOS 標準のタブのまま。標準の「×」はカーソルを乗せたときしか出ないので、タブの付属のビュー（`NSWindowTab.accessoryView`）に、いつも見える「×」を置いた。選んでいないタブでも、そのタブだけを閉じられる
  - ツールバーは、説明が項目の外枠にしか付かず、ボタン本体（カーソルが乗る部分）には付いていなかった。そのため macOS 26 では説明が出なかった。ボタンを自前の NSButton にして、説明を本体に付けた。見た目は変わらない
  - 説明は「何に対して何をするか」が分かる書き方にし、ショートカットを添えた。例：「選んだ項目のパスをコピー。選んでいなければ表示中のフォルダのパス（⌥⌘C）」。パスバーのコピーは、コピーされるパスそのものを出す
  - パスバーのコピーのボタンは、パスバーの右端ではなく、パスの末尾（今いるフォルダの名前）のすぐ右に置いた。何のパスをコピーするボタンか、並びで分かるようにするため。長いパスでは末尾とボタンが見えるように右へ寄せる
- 追加 `Macorn/Window/TabCloseButton.swift` — タブの右端の「×」。カーソルを乗せると背景を薄く出す
- 追加 `Macorn/Window/ToolbarButtonItem.swift` — 説明をボタン本体に付けるツールバーの項目。有効・無効は送り先に尋ねて決める
- 変更 `Macorn/Window/BrowserWindowController.swift` — 各タブに「×」を付ける。ツールバーの項目を ToolbarButtonItem にし、短い名前と説明を分ける。2画面表示とお気に入りは、今の状態に合わせて説明を変える
- 変更 `Macorn/Browser/PathBarView.swift` — コピーのボタンを、パスの末尾のすぐ右に移す。ボタンの説明に、コピーされるパスを出す（このボタンは選択に関係なく表示中のフォルダをコピーするため、⌥⌘C の表記は外す）。パンくずの説明に移動先と右クリックの使い方を出す
- 変更 `Macorn/Sidebar/SidebarViewController.swift`・`Macorn/Preview/FilePreviewController.swift` — 取り出す・タグを作る・ブラウザで開くなどの説明を、対象が分かる書き方にする
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順を足す（`tabinfo`・`tabclose:番号`・`tooltips`・`toolbarclick:名前`）

### Macorn：LP を検索エンジンに見つけてもらいやすくする

- **きっかけ**：konta の質問（2026-11-01）「Google 検索時にヒットするようなメタ情報の設定などちゃんとできていますか？」→ 足りないものを「足して」
- **意図・方針**：タイトル・説明文・正規の URL・OGP・`lang` はすでにあった。なかった robots.txt・サイトマップ・構造化データ（JSON-LD）を足した。構造化データの版とサイトマップの更新日は、公開のたびに古くならないよう `scripts/release.sh --publish` が書き換える。Google Search Console への登録は Google アカウントでのログインが要るため、konta が行う
- 追加 `site/robots.txt` — すべてのクローラーに許可し、サイトマップの場所を知らせる
- 追加 `site/sitemap.xml` — LP（1ページ）だけのサイトマップ
- 変更 `site/index.html` — `og:site_name`・`og:locale` と、構造化データ（WebSite と SoftwareApplication。名前・説明・対応 OS・版・ダウンロード先・無料）を足す
- 変更 `scripts/release.sh` — `--publish` で、構造化データの `softwareVersion` とサイトマップの `lastmod` も書き換える

### Macorn：Zenn の記事を今のアプリに合わせて見直す

- **きっかけ**：konta の依頼（2026-11-01）「記事を全体レビューして」→ 指摘の 1〜4 を「直して」
- **意図・方針**：記事に書いたキー・機能は今のアプリと合っていた。0.3.5・0.3.6 で古くなった記述と、同じものの呼び方のゆれだけを直した。図の言葉（「進み具合」）は変えられないので、本文をそれにそろえた。Zenn の下書きにも同じ変更を入れ、原稿と1行ずつ一致することを確かめた
- 変更 `promo/zenn/macorn-intro.md` — アップデートの説明に「今すぐ更新」で自動で入れ替わることを足す。プレビューと「Macorn で開ける」種類に CSV を足す。「ステータス」「状態」を「進み具合」にそろえ、タグの例を `会社/A社` `案件/X` `進み具合/進行中` にする。Zenn の下書きで外れていた、タグとセクションの使い分けの結論の太字を戻す（原稿は元から太字）

### Macorn：LP の立体図から xyz の座標軸を外す

- **きっかけ**：konta の指摘「xyz の座標軸の表現は不要かも」
- **意図・方針**：平面の名前（「実際のフォルダ（パス）」「次元 1：案件」など）で何を重ねているかは伝わるので、左下の座標軸と「z = 重ねる次元」「x, y = パス」の凡例を消した。Zenn の記事の冒頭の図も同じ見た目に作り直した（ヘッドレスの Chrome で一時的な表示用ページを描いて書き出し、表示用ページは消した）。Zenn の画像は変換のサービスが古い画像を覚えているので、記事の URL に `?v=2` を付けた
- 変更 `site/dims.js`、`site/style.css` — 座標軸・凡例と、その見た目を消す
- 変更 `site/assets/article/dimensions.webp`、`promo/zenn/macorn-intro.md` — 座標軸のない記事用の図と、その参照

### Macorn：バージョン 0.3.6 を LP で公開する

- **きっかけ**：konta の依頼「0.3.6 で公開」（CSV・TSV のプレビューと、Macorn で開けるようにしたことを受けて）
- **意図・方針**：0.3.5 → 0.3.6（ビルド番号は 8 → 9）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。0.3.5 の利用者は「今すぐ更新」で自動で入れ替えられる初めての版になる
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.6、`CURRENT_PROJECT_VERSION` を 9 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.6 の DMG・表記・最新版の情報

### Macorn：CSV・TSV を表でプレビューし、Macorn で開けるようにする

- **きっかけ**：konta の依頼「csv も開けるようにしたい」
- **意図・方針**
  - これまで CSV はプレビューできなかった。Markdown と同じく自前で HTML にして、プレビューの Web の領域に表で出す（外部ライブラリなし）
  - 読み込みは RFC 4180 に沿い、引用符で囲んだ値（中のカンマ・改行・`""`）に対応。日本の Excel が書く Shift_JIS も読む（BOM → UTF-8 → Shift_JIS → UTF-16 の順に試す）。区切りは .tsv ならタブ、それ以外は1行目に多いもの（カンマ・タブ・セミコロン）
  - 1行目を見出しにし、見出しと行番号はスクロールしても残す。数値は右寄せ。列が詰まって1文字ずつ折り返さないよう、値は折り返さず横にスクロールし、長い値は省略してマウスを乗せると全文を出す。重くならないよう先頭の 2000 行まで
  - ほかのプレビューできる種類と同じく、「このアプリケーションで開く」に出し、設定の「ファイルを Macorn で開く」で既定のアプリにもできる。プレビューの上部のボタンで表計算などほかのアプリでも開ける
- 追加 `Macorn/Preview/CSVRenderer.swift` — CSV・TSV の読み込みと表の HTML
- 変更 `Macorn/Preview/FilePreviewController.swift` — プレビューの種類に CSV を足す
- 変更 `Macorn/Integration/DefaultFileApps.swift`、`Macorn-Info.plist` — CSV・TSV を Macorn で開ける種類に足す
- 追加 `MacornTests/CSVRendererTests.swift` — 引用符・改行・区切りの判定・Shift_JIS・表の HTML・行数の上限
- 変更 `AGENTS.md`、`docs/REQUIREMENTS.md`、`README.md` — プレビューと開ける種類に CSV を足す

### Macorn：バージョン 0.3.5 を LP で公開する

- **きっかけ**：konta の依頼「0.3.5 で公開」（「今すぐ更新」での自動の入れ替えを受けて）
- **意図・方針**：0.3.4 → 0.3.5（ビルド番号は 7 → 8）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。0.3.4 以前からはこの版への入れ替えだけ手動で、0.3.5 からは次の版を「今すぐ更新」で自動で入れ替えられる
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.5、`CURRENT_PROJECT_VERSION` を 8 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.5 の DMG・表記・最新版の情報

## 2026-10-31

### Macorn：「今すぐ更新」で自動で入れ替えて開き直す

- **きっかけ**：konta の指摘「アップデートを押すとブラウザから DMG をダウンロードし、手動で移動・上書きしないといけない。更新を押したら勝手に更新されてアプリが再起動するようにできないのか」→ 選択「作る（LP も公開）」
- **意図・方針**
  - **前提の変更**：「入れ替えは手動」（2026-10-27）をやめ、外部ライブラリなしのまま自動で入れ替える。Sparkle は使わない
  - 流れは、ダウンロード（進み具合とキャンセルの窓）→ DMG を見えない形で開く → 中の Macorn を確かめる → 一時フォルダへ写して DMG を閉じる → Macorn を終えてから、今の場所の Macorn と入れ替えて開き直す。入れ替えに失敗したら元の Macorn に戻す
  - 確かめるのは、Apple が認めた証明書で今の Macorn と同じ開発チーム（`anchor apple generic and certificate leaf[subject.OU]`）、同じアプリ ID、知らされた版であること。ダウンロード先が差し替えられても、別人の署名のアプリには入れ替わらない
  - 開発用ビルド（簡易署名）・書き込めない場所・確かめられないときは入れ替えず、理由を出してブラウザでのダウンロードに戻す。0.3.4 以前の版からは、もう一度だけ手動で入れ替える必要がある
  - 確認は作業用フォルダに写した開発用ビルドで、公開中の 0.3.4 の DMG に入れ替わって開き直すこと、違うチームを指定したら断ること、DMG と一時フォルダが残らないことを見た
- 追加 `Macorn/App/UpdateInstaller.swift` — ダウンロード・確認・入れ替え・開き直しと、進み具合の窓
- 変更 `Macorn/App/UpdateChecker.swift` — 自動で入れ替えられるときはアラートのボタンを「今すぐ更新」にする
- 変更 `Macorn/App/DebugAutomation.swift` — 確認用の手順 `updateinstall:<version.json の URL>`
- 追加 `MacornTests/UpdateInstallerTests.swift` — ほかのアプリ・版違い・簡易署名を受け入れないこと
- 変更 `AGENTS.md`、`docs/REQUIREMENTS.md`、`README.md` — 前提と、確認用の環境変数 `MACORN_UPDATE_TEAM`

### Macorn：タグとセクションの使い分けを、記事と LP に書く

- **きっかけ**：konta の質問「タグとセクションの使い分けはどう説明するか」→ 依頼「記事と LP に足す」
- **意図・方針**
  - ひとことで「タグは『そのファイルが何か』、セクションは『どこから開くか』」。コンセプトの言葉に合わせ「次元を足すのがタグ、次元への近道を並べるのがセクション」とした
  - 役割・付くもの・使い方・外すと・例の5つで比べる表と、迷ったときの決め方、組み合わせの例（「今週の作業」セクションに、タグ `ステータス/進行中`・毎日開くフォルダ・仕様書を並べる）を載せた
  - 記事はコンセプトの節に「タグとセクションの使い分け」の小見出しを足し、Zenn の下書きにも反映した。LP はコンセプトの節の2枚のカードの下に比べる表を足した（スマホの幅では項目名を上に出して2列にする）
- 変更 `promo/zenn/macorn-intro.md` — 使い分けの小見出し
- 変更 `site/index.html`、`site/style.css` — 使い分けの表

### Macorn：Zenn の記事の「切り口」の例を、会社・案件・ステータスにする

- **きっかけ**：konta の依頼「ステータスごとの未着手・進行中・完了や、案件や会社名などでの切り口が多いので、例示を修正してほしい」（「案件A のもの」「いま進行中のもの」「レビュー待ちのもの」の部分）
- **意図・方針**：よく使う切り口に合わせ、「会社ごと」「案件ごと」「未着手・進行中・完了といったステータスごと」にした。Zenn の下書きにも同じ文を反映した
- 変更 `promo/zenn/macorn-intro.md` — 導入の例示

### Macorn：Zenn の記事の3段階の図で、図を縦の真ん中に置く

- **きっかけ**：konta の指摘「Zenn においてイラストが下の方に寄っているので修正してほしい」（STEP 01 の画像）
- **意図・方針**
  - 3段階の図は、LP では3枚の床の高さをそろえるため床を下の方に固定している。記事の画像は1枚ずつ見せるので、そろえる必要がない。`site/dims.js` の小さな図に `data-center="true"`（図全体を縦の真ん中に置く。背の高い STEP 03 は少し小さくして枠に収める）を足し、記事の画像だけそれで描き直した。LP の見た目は変えていない
  - 画像の左右の幅を半分ずつに固定し（文字の長さで図の幅が変わらないように）、STEP 03 の説明文の改行を整えた。3枚とも作り直した（`steps-01.webp`〜`steps-03.webp`）
  - Zenn は一度読み込んだ画像を覚えているので、LP に公開してから、記事の画像の URL の末尾を `?v=2` に変える
- 変更 `site/dims.js` — 小さな図を縦の真ん中に置く指定
- 変更 `site/assets/article/steps-01.webp`〜`steps-03.webp` — 作り直した記事用の図
- 変更 `promo/zenn/macorn-intro.md` — 画像の URL を `?v=2` に

### Macorn：バージョン 0.3.4 を LP で公開する

- **きっかけ**：konta の依頼「0.3.4 で公開」（パスのコピーのボタンと、右クリックの「セクションに置く」を受けて）
- **意図・方針**：0.3.3 → 0.3.4（ビルド番号は 6 → 7）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。0.3.0 以降の利用者には起動時に知らせが出る
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.4、`CURRENT_PROJECT_VERSION` を 7 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.4 の DMG・表記・最新版の情報

### Macorn：パスをすぐコピーできるようにし、一覧の右クリックからセクションに置けるようにする

- **きっかけ**：konta の依頼「パスのコピーもすぐにできるようにしてほしい」「フォルダのメニューにおいてもセクションを指定できるようにしたい」
- **意図・方針**
  - パスのコピー：これまでは ⌥⌘C とメニューバーだけで、一覧の右クリックにもなかった。次の3か所に足した
    - ツールバーのボタン（⌥⌘C と同じ。選択中の項目、なければ表示中のフォルダ）
    - パスバーの右端のボタン（表示中のフォルダ。押すとしばらくチェックの印になる）
    - 一覧の右クリックの「パスをコピー」と「ほかの形式でパスをコピー」（~ 形式・リポジトリからの相対パス・シェル用）。何もない所の右クリックにも出す
  - セクション：一覧の右クリック（項目・何もない所）に「セクションに置く」を足した。自分で作ったセクションが並び、置いてあるものには印が付く（一部だけなら「−」）。選ぶと置き、すべて置いてあれば外す。「新しいセクションを作って置く…」で名前を聞いて作り、そこに置く。セクションは見た目だけのまとまりなので、置いても項目には何も付かない
  - 確認：ユニットテスト（置く・足りない分だけ置く・すべて置いてあれば外す）を足した（139 件）。自動操作で、ツールバーとパスバーのボタンでパスがコピーされることを確かめた（クリップボードは確認の前の内容に戻した）
- 追加 `Macorn/Browser/FileBrowserViewController+Sections.swift` — 右クリックの「パスをコピー」「セクションに置く」
- 変更 `Macorn/Browser/FileBrowserViewController.swift`、`Macorn/Browser/PathBarView.swift`、`Macorn/Window/BrowserWindowController.swift`、`Macorn/Sidebar/SidebarPrompts.swift` — メニュー・パスバー・ツールバー・新しいセクションを作って置く
- 変更 `MacornTests/SidebarTests.swift` — セクションに置くテスト
- 変更 `README.md`、`docs/REQUIREMENTS.md` — 操作の説明とテストの件数

### Macorn：Zenn の記事の3段階の図を、1枚ずつの横長の画像に分ける

- **きっかけ**：konta の依頼「コンセプト：整理の次元は、いくつでも のイラストに関して、3つをまとめた画像を貼るのではなく、3つの独立した画像にして貼るようにして欲しい。現状の貼り方だと文章が小さく見えているのでそれも解消したい」
- **意図・方針**
  - 3枚のカードを横に並べた1枚の画像（幅 1415px）は、記事の本文の幅（約 700px）に縮めて表示されるため、文字が実寸の半分ほどになっていた。カードを1枚ずつの画像にし、記事の幅で読めるよう、左に図・右に「STEP・見出し・説明文」を置く横長の形に組み直した（説明文 22px・見出し 34px で描き、記事の幅に縮めても説明文が約 16px で読める）
  - 図は LP の `site/dims.js` と `site/style.css` をそのまま使い、記事用の並べ方と文字の大きさだけを一時的な表示用ページで上書きして、ヘッドレスの Chrome で1枚ずつ切り抜いた（2倍の解像度）。表示用ページはリポジトリに置いていない。LP の3段階のカードは変えていない
  - 旧 `steps.webp` は記事から参照しなくなったが、消さずに残している
  - 公開の直後、Zenn で3枚が表示されなかった。Zenn は画像を Cloudinary 経由で読み込み、LP に画像を置く前に下書きを保存したときの「見つからない」を覚えていたため。画像の URL の末尾に `?v=1` を付けて読み直させ、表示されることを確かめた（次に画像を差し替えるときも、LP に先に公開してから記事に貼るか、`?v=` を変える）
- 変更 `promo/zenn/macorn-intro.md` — コンセプトの節の図を、1枚の `steps.webp` から3枚の `steps-01.webp`〜`steps-03.webp` に差し替えた
- 追加 `site/assets/article/steps-01.webp`、`steps-02.webp`、`steps-03.webp` — 記事用の3段階の図（1枚ずつ）

### Macorn：Zenn の紹介記事の原稿を、新しいコンセプトと機能に合わせて書き直す

- **きっかけ**：konta の依頼「ここまでの内容を Zenn の記事に反映させてほしい」
- **意図・方針**
  - タイトルを「フォルダはそのまま、整理はいくつもの次元で。開発者向け macOS ファイルマネージャー『Macorn』を作りました」にし、導入を「フォルダの階層は1つしか持てないが、見たい切り口はいくつもある」という問題から始めた。コンセプトの節（整理の次元を必要なだけ重ねる、ファイルは動かさない、同じファイルが複数の次元に並ぶ）を足し、機能の並びもタグ・セクションを先頭にした
  - 10/27 以降に足した機能（PDF などを Macorn で開く・既定のアプリ、パスバーの1回クリック、新規フォルダ・ファイルのボタン、「Finder に表示」、アプリケーションへの移動、アップデートの通知）を反映した。公証の一文は LP と同じく載せない。AI で作ったことは書かない（前回の方針のまま）
  - LP の立体図と3段階のカードを、記事に載せる画像として書き出した（ヘッドレスの Chrome で一時的な表示用ページを描いて切り抜き、表示用ページは消した）。画像は LP の `site/assets/article/` に置き、記事から URL で参照する
- 変更 `promo/zenn/macorn-intro.md` — 記事の原稿。konta の依頼「『フォルダの階層は、1つしか持てません』に、通常の Finder などでは、といった説明を付けてほしい」を受け、冒頭を「Finder をはじめとするふつうのファイルマネージャーでは、ファイルの置き場所はフォルダの階層の1つだけ。1つのファイルは、1つのフォルダにしか入れられない」にした
- 追加 `site/assets/article/dimensions.webp`、`site/assets/article/steps.webp` — 記事用の図

### Macorn：立体図の床を「ふつうのフォルダの木」として描く

- **きっかけ**：konta の指摘「整理の次元 0 の図がよくわからない。通常のフォルダ構成を表現している感じが伝わらない」
- **意図・方針**
  - 床（実際のフォルダ）を、点を散らした平面から、フォルダの木に描き直した。`~` から Downloads・work・Documents・dev、さらに client-a・notes・sandbox を通って各ファイルへ、ツリー表示の罫線と同じ形の枝でつなぐ（深さを x、兄弟を y に並べる）。節には立てたフォルダ（青）／ファイル（白）の印を置いた
  - ヒーローの図では、節ごとに `work/` `client-a/` のような名前も出す。床が上の次元に隠れないよう、床から最初の次元までを広めに空け、全体を少し大きく、見下ろす角度を少し深くした
  - 3段階のカードの図は、深さが右・兄弟が奥に並ぶ、ふだんのフォルダの木に近い向きを、低い角度（横寄り。見下ろす角度 22°）から見る。konta の指摘「整理の次元1 などで、縦方向の関係性がこの視点だとわかりにくいので、もう少し横から見た視点に」を受け、重ねた次元の上下の間が画面でも開いて見えるようにした。小さな図では名前が重なるので、根（`~`）と枝の先（spec.pdf・api/・design.md・mock-server/）だけに名前を出す。床は大きくし、3枚で高さをそろえたまま、上の次元の間を詰めた。上の項目は、その向きで画面の横一列に並ぶようにした
  - 確認：手元の LP で、PC とスマホの幅で表示を確かめた
- 変更 `site/dims.js`、`site/style.css`、`site/index.html` — 床のフォルダの木、図の大きさと向き

### Macorn：LP の3段階のカードを作り直す（矢印をやめる）

- **きっかけ**：konta の指摘「矢印の位置がおかしい」→「矢印はそもそもいるのか。カードのレイアウトをもっと洗練して」
- **意図・方針**
  - 矢印はやめた。STEP 01〜03 の番号と、図が段階ごとに積み上がることで順は伝わる
  - 3枚とも、床（フォルダの平面）の高さをそろえた（`site/dims.js` の小さな図は床の中心を固定して描く）。並べると、上へ次元が積み上がっていくように見える
  - カードは上半分を図の面（淡い光を当てた紺）、下半分を文字にした。図の左上に「整理の次元 0 / 1 / 2 +」の札を付け、文字は「STEP 01」と見出し・説明の順にした。目指す形の3枚目だけ、縁を橙にして少し強調した
  - 確認：手元の LP で、PC とスマホの幅で表示を確かめた
- 変更 `site/index.html`、`site/style.css`、`site/dims.js` — 3段階のカード

### Macorn：LP を「整理の次元を必要なだけ重ねる」コンセプトに直す

- **きっかけ**：konta の指示「このアプリは単に通常のフォルダ構成と独立した一次元の整理ではなく、必要に応じて次元数を増やして整理できることがコンセプトなので、それが伝わるような図解、キャッチフレーズ、説明にして欲しい。図解も一つである必要はないのでブラッシュアップして欲しい」
- **意図・方針**
  - 前提の変更：コンセプトの核を「パスとは別の次元での整理」から「整理の次元を必要なだけ重ねられること」に広げた（要件定義書 D7・AGENTS.md）。次元はタグの階層ごと（案件・進み具合・テーマなど）で、同じファイルがいくつもの次元に同時に並ぶ
  - キャッチフレーズを「フォルダはそのまま。整理は、いくつもの次元で。」に、説明を「実際のフォルダとは別に、整理の次元を必要なだけ重ねられる。案件・進み具合・テーマ……同じファイルを、見たい切り口ごとに並べ直せる」にした。タイトル・説明文・OGP の文言も合わせた
  - ヒーローの立体図：実際のフォルダの上に「次元 1：案件」（案件A）と「次元 2：進み具合」（進行中・レビュー待ち）を重ね、いちばん上に「＋ 次元を足す」点線の平面を置いた。api と spec.pdf は2つの次元に同時に並び、どれも点線で実際の場所につながる。グループの名前は帯の下、次元の名前は平面の右に出し、名札と重ならないようにした
  - 図をもう1つ足した：コンセプトの節に「フォルダだけ → 次元を1つ足す → 必要なだけ重ねる」の3段階の小さな図（回さない）。見出しは「整理の次元は、いくつでも。」
  - 図は `site/dims.js` で同じ部品から描く（ヒーローは回せる、3段階の図は小さく簡略に）
  - 3つの柱の1つ目を「次元を、必要なだけ足す」に、コンセプトの節の「タグとセクション」の説明を「タグの階層ごとに独立した次元」にした
  - 確認：手元の LP で、PC とスマホの幅の表示と、立体図が回ることを確かめた
- 変更 `site/index.html`、`site/style.css`、`site/dims.js` — キャッチフレーズ・説明・2つの図
- 変更 `AGENTS.md`、`docs/REQUIREMENTS.md`、`README.md` — コンセプトの核（前提の変更）と LP の説明

### Macorn：LP のコンセプトの節から軸の表記を消す

- **きっかけ**：konta の指示「x, y ── パスの次元、z ── 整理の次元というように軸まで明記しなくていい」
- **意図・方針**：コンセプトの節の2枚のカードの見出しの上は、「パスの次元」「整理の次元」とだけ書く。ヒーローの立体図の座標軸（x・y・z）はそのまま残した
- 変更 `site/index.html` — カードの小見出し

### Macorn：LP の入手の欄から公証の一文を消す

- **きっかけ**：konta の質問・依頼「『Apple の確認（公証）を受けたアプリなので、ダウンロードしてそのまま安全に開けます』もよく使われているか。一般的なアプリの説明にないなら消してほしい」
- **意図・方針**：直接配布の Mac アプリの LP でも、公証は今では当たり前のことで、本文に書くことはあまりない（書くとしてもよくある質問やインストールの注意書き）。本文からは消し、「Finder といっしょに使える」「タグやセクションは Mac の中だけに保存し、ファイルには手を加えない」の2文を残した
- 変更 `site/index.html` — 入手の欄の文章

### Macorn：紹介動画を新しいコンセプトで作り直し、立体図の点を洗練させる

- **きっかけ**：konta の依頼「動画も直す」（LP のコンセプト変更を受けて）と、「三次元座標における点がダサいので、もっと洗練させたデザインにして欲しい」
- **意図・方針**
  - 動画：タイトルを「フォルダはそのまま。整理は、別の次元で。」（下に「タグとセクションで、ファイルを動かさずに整理する macOS ファイルマネージャー」）にし、場面の順を LP と同じく、タグ → セクション → 2画面 → コマンドパレット → ターミナル・Git → プレビューにした。字幕もコンセプトに合わせた（タグを開くと項目が1つに並び、ファイルは動かない／セクションは見た目だけのまとまり）。撮影した画面では2つの項目が同じフォルダにあるので、「別々の場所」ではなく「どこにあっても」と書いた。画面は撮り直していない（72 秒のまま）
  - LP の動画と再生前の画像を差し替えた
  - 立体図の点：ただの丸をやめ、実際の場所は平面に寝かせた輪と芯（整理の次元とつながるものは橙の波紋が広がる）、整理の次元の項目は平面に刺したピンから細い線を立てて浮かべた名札（フォルダ／ファイルの印と名前）にした。点線は上の橙から下の白へ溶けるグラデーションにした。輪は見下ろす角度に合わせてつぶれ、回しても平面に寝て見える。名札の間が詰まったので、上の項目の間を広げた
  - スマホの幅では名札を大きくし、線の長さを互い違いにして重ならないようにした。上の平面の名前とセクションの名前が重なるので、スマホではセクションの名前を省いた
  - 確認：書き出した動画の各場面を一覧にして確かめた。LP は PC・スマホの幅で表示とドラッグで回ることを確かめた
- 変更 `promo/video/src/Flow.tsx`、`promo/video/README.md` — タイトル・場面の順・字幕
- 変更 `site/assets/macorn-promo.mp4`、`site/assets/video-poster.jpg` — 作り直した動画
- 変更 `site/dims.js`、`site/style.css` — 立体図の印・名札・点線のデザイン
- 変更 `site/index.html` — 入手の欄の文章を、技術用語（Developer ID の署名）を使わず「Apple の確認（公証）を受けたので安全に開ける」と結果で伝える形にした（konta の質問「この文章は一般的か」への回答と、差し替えの指示による）

### Macorn：バージョン 0.3.3 を LP で公開する

- **きっかけ**：konta の依頼「公開して 0.3.3 も」（パスバーの1回クリック・新規フォルダ／ファイルのボタンと、LP の作り直しを受けて）
- **意図・方針**：アプリの変更（パスバー・作成のボタン）を配る。0.3.2 → 0.3.3（ビルド番号は 5 → 6）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替え、作り直した LP と一緒に公開した。0.3.0 以降の利用者には起動時に知らせが出る
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.3、`CURRENT_PROJECT_VERSION` を 6 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.3 の DMG・表記・最新版の情報

### Macorn：LP を「仮想的な整理」が主役の構成にし、回せる立体図を入れる

- **きっかけ**：konta の指示「このアプリのコンセプトとしては、実際のパスとは関係のない仮想的な構造整理（セクション、タグによる管理）がコアになるので、それがわかるような LP に修正して欲しい。三次元座標などを用いて実際のフォルダ構成と仮想的な構成（別次元）を表現したキャッチーな図も入れて欲しい」。続けて「LP 上でユーザーが三次元図をドラッグ操作などで回転できるようにしてかっこよくしたい」
- **意図・方針**
  - 前提の変更：コンセプトの核を「2画面・パレット・ターミナル連携」から「実際のパスとは別の次元での整理（タグ・セクション）」に移した。2画面などは、その中をすばやく動くための操作として残す（要件定義書に D7 を追加、D2 に注記）
  - ヒーロー：見出しを「フォルダはそのまま。整理は、別の次元で。」にし、画面写真の代わりに立体図を置いた。下の平面（x, y）は実際のフォルダの階層（`~` から各パスへの枝）、上に浮かぶ平面（z）はセクション「進行中」とタグ「案件A」で並べた4つのファイル。同じファイルを点線でつなぎ、左下に x・y＝パス、z＝整理の座標軸を出す
  - 立体図は `site/dims.js` が 3次元の座標から正投影で描く（外部ライブラリなし）。横のドラッグで縦の軸まわりに、縦のドラッグで見下ろす角度（8〜72°。上の平面がいつも上に見える範囲）を変える。タッチでは横だけ回し、縦はページのスクロールに残す。矢印キーでも回せ、ダブルクリックで元の向きに戻る。触る前はゆっくり左右に揺らして回せることを見せ、離したあとは少し惰性で回る。動きを減らす設定の人には揺らさない
  - 回しても文字が重ならないよう、上の平面の名前はいちばん上の角の上、下の平面の名前はいちばん下の角の下、セクションの名前は枠の角に付けて動かす。スマホの幅では、下の平面の長いパスを省き、名前を大きくして上下に互い違いに出す
  - 3つの柱を「タグで束ねる／セクションで並べる／キーボードで動く」に替え、「2つの次元」を比べるコンセプトの節（実際のフォルダ／タグとセクション）を動画の前に足した。機能の並びもタグ・セクションを先頭にした。タイトル・説明文・OGP の文言も合わせた（OGP の画像は前のまま）
  - 確認：手元の LP で、PC とスマホの幅の表示、ドラッグで回ること（座標軸も一緒に回る）、横にはみ出さないことを確かめた
- 追加 `site/dims.js` — 回せる立体図
- 変更 `site/index.html`、`site/style.css` — ヒーロー・3つの柱・コンセプトの節・機能の並び
- 変更 `AGENTS.md`、`docs/REQUIREMENTS.md`、`README.md` — コンセプトの核（前提の変更）と LP の説明

### Macorn：パスバーを1回のクリックで入力にし、新規フォルダ・ファイルのボタンを付ける

- **きっかけ**：konta の依頼「アプリ上部のパス選択において、一回クリックで直接入力が可能になるようにして欲しい」「フォルダ作成、ファイル作成のボタンを用意して欲しい」
- **意図・方針**
  - パスバー：これまでは空いている所のダブルクリックで入力になった。空いている所と、今いるフォルダの名前（いちばん右）を1回クリックすると入力になるようにした。今いるフォルダへの移動は何も起きないので、入力に割り当てた。親のフォルダの名前のクリックは、これまでどおりそのフォルダへ移動する（よく使う操作を残すため）
  - ボタン：ツールバーの ★ の左に「新規フォルダ」「新規ファイル」を置いた。メニューの ⇧⌘N / ⌥⌘N と同じく、操作対象の画面の表示中のフォルダに作り、名前の変更を始める。タグの一覧を表示しているときは押せない
  - 確認：自動操作で、空いている所・今いるフォルダの名前のクリックで入力になり（Esc で戻る）、親の名前のクリックで移動すること、2つのボタンでフォルダとファイルができることを確かめた。ユニットテストは 138 件
- 変更 `Macorn/Browser/PathBarView.swift`、`Macorn/Browser/FileBrowserViewController.swift` — 1回のクリックで入力
- 変更 `Macorn/Window/BrowserWindowController.swift` — 新規フォルダ・新規ファイルのボタン
- 変更 `Macorn/App/DebugAutomation.swift` — 手順 `clickpath:<横の位置>`、`toolbarclick:<識別子>` を追加
- 変更 `README.md`、`docs/REQUIREMENTS.md` — 操作の説明

## 2026-10-27

### Macorn：Zenn の紹介記事の原稿を書く

- **きっかけ**：konta の依頼「これを Zenn の記事にして投稿しようと思うので、Chrome 経由で記事を書いてほしい」。選択：主題は Macorn の紹介、AI で作ったことは書かない、Zenn では下書き保存まで（公開は konta が行う）
- **意図・方針**
  - 開発者が Finder とターミナルの往復で感じる手間から入り、6つの主な機能（2画面・コマンドパレット・ターミナル連携・タグ・サイドバー・プレビュー）を LP の画面写真つきで紹介する。最後に入手方法と、データは Mac の中に保存すること
  - 画像は LP（https://macorn.vercel.app/assets/screens/）のものをそのまま使う。リポジトリは非公開なのでリンクしない
  - 書いた内容（対応するターミナル・エディタ、Git の表示など）はコードと照らし合わせた
  - Zenn の CLI と同じ形式（frontmatter つき、`published: false`）で手元に置き、Chrome から Zenn の Web エディタに入れて**下書き保存**した（https://zenn.dev/konta8420/articles/da5fc2b984e901 。公開は konta が行う）。絵文字 🐿️、カテゴリー Tech
  - トピックの「mac」は Zenn では「macOS」と表示され、「macos」と重なったので「terminal」に替えた（手元の原稿もそろえた）
  - 下書きのプレビューで、見出し・表・7枚の画像がすべて表示されることを確かめた
- 追加 `promo/zenn/macorn-intro.md` — 記事の原稿

### Macorn：バージョン 0.3.2 を LP で公開する

- **きっかけ**：konta の依頼「PDF の既定は Macorn のままでいい。変更をコミットして push し、0.3.2 として LP に公開して」
- **意図・方針**：PDF・Markdown・画像などを Macorn で開ける版を配る。0.3.1 → 0.3.2（ビルド番号は 4 → 5）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた。0.3.0 以降の利用者には、起動時に新しい版の知らせが出る
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.2、`CURRENT_PROJECT_VERSION` を 5 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.2 の DMG・表記・最新版の情報

### Macorn：PDF・Markdown・画像などを Macorn で開けるようにする

- **きっかけ**：konta の質問「Claude などから PDF を開くとき Finder は候補に出るが Macorn が出ない。既定で Macorn で開く設定はできないか」→ 依頼「PDF・Markdown・画像などプレビューできる種類を Macorn で開けるようにして（『このアプリケーションで開く』に出す）、設定から既定のアプリにもできるようにして」。途中で konta の指摘「アプリ内で PDF を選択したらプレビュー表示がされるようにしてほしい。今は新規でタブが表示されてしまう」
- **意図・方針**
  - 前提の変更：「ファイルの種類は対象外」をやめ、プレビューできる種類（PDF・Markdown・HTML・画像・動画・音声）を開けるアプリとして Info.plist に申告した。書類（Word など）はクイックルックでしか見られないので入れない。Alternate なので、入れただけでは既定にならない
  - 設定の「連携 › ファイルを Macorn で開く」で種類ごとに既定のアプリにできる。macOS の既定は具体的な種類ごとなので、画像なら PNG・JPEG・GIF・HEIC・WebP などをまとめて切り替える。オンにする前のアプリを覚えておき、オフでそれに戻す
  - 試すと、macOS 26 では既定のアプリの変更に利用者の確認が要った。`NSWorkspace.setDefaultApplication` は確認を出し（画面のないコマンドからは「取り消し」になる）、`LSSetDefaultRoleHandlerForContentType` は成功を返しても変わらない。設定の切り替えはアプリの中から呼ぶので、確認が出てそこで決める
  - ほかのアプリから開いたファイルは、フォルダの中で選んでプレビューを出す（プレビューを切っていても、そのファイルを選んでいる間は出す）。そのフォルダをすでに表示しているタブがあれば、新しいタブは作らずそれを使う
  - konta の指摘への対応：PDF の既定を Macorn にすると、Macorn の中で PDF を開いたとき自分に戻ってきて新しいタブが開いていた。既定が Macorn のファイルは外に出さず、その場でプレビューするようにした。HTML のプレビューの「ブラウザで開く」も、既定が Macorn ならほかのアプリで開く
  - 確認：「このアプリケーションで開く」の候補に Macorn が入ること（テキストには入らないこと）、PDF の既定が Macorn のときに Macorn の中で開くと同じタブでプレビューが出ること（プレビューを切った状態で）を確かめた。ユニットテストは 138 件
  - 試験の途中で konta の PDF の既定が Macorn になった（確認の画面で承認されたため）。konta の判断で、そのまま Macorn にしておく。戻すには設定の切り替えをオフにする（macOS の確認が出る）
- 追加 `Macorn/Integration/DefaultFileApps.swift`、`MacornTests/DefaultFileAppsTests.swift`
- 変更 `Macorn-Info.plist` — 開ける種類の申告と Markdown の種類の宣言
- 変更 `Macorn/Settings/SettingsView.swift`、`Macorn/Model/Preferences.swift` — 設定の切り替えと、前のアプリの記憶
- 変更 `Macorn/App/AppDelegate.swift`、`Macorn/Browser/FileBrowserViewController.swift`、`Macorn/Browser/FileBrowserViewController+Preview.swift`、`Macorn/Preview/FilePreviewController.swift` — 開いたファイルのプレビュー、その場でのプレビュー、既存のタブの再利用
- 変更 `Macorn/App/DebugAutomation.swift` — 手順 `fileapp:<種類>:on|off`、`windows` にプレビューの表示を追加
- 変更 `README.md`、`AGENTS.md`、`docs/REQUIREMENTS.md` — 使い方と前提

### Macorn：DMG にドラッグの案内を付け、「アプリケーション」への移動を尋ねる（0.3.1 を公開）

- **きっかけ**：konta の指摘「インストール時にアプリケーションフォルダに入らない上、ドラッグアンドドロップを促しもしない」→ 依頼「DMG のウィンドウにドラッグを促す背景と配置を付け、アプリにも『アプリケーション』フォルダへ移すかを尋ねる仕組みを入れて。できたら 0.3.1 として LP に公開して」
- **意図・方針**
  - これまでの DMG はフォルダをそのまま固めただけで、ウィンドウの見た目を決めていなかった。konta は DMG の中から直接 Macorn を開いていた
  - DMG：ブランドのクリームの背景に「Macorn を『アプリケーション』へドラッグ」と矢印を描き（Swift で描く。外部ツールなし）、矢印の左右に Macorn と「アプリケーション」を 128px で並べる。見た目は書き込みできる DMG を Finder に設定させてから圧縮する（`.DS_Store` に残る）
  - macOS 26 の Finder はツールバーを隠せないので、その分ウィンドウを高くした。Finder のアイコンの位置は中心より少し上を指すので、矢印の高さに合うよう 45 上にずらした（実際に開いて撮って合わせた）。同じ名前の DMG がほかに開いていても取り違えないよう、Finder にはマウントした場所で指す
  - 隠しファイルを表示する設定の人にも余計なものが見えにくいよう、`.fseventsd` は消し、背景のフォルダは下の見えない所へ置く（その人にはスクロールバーが出る）
  - アプリ：「アプリケーション」（/Applications・~/Applications）の外から起動したら、移動するかを尋ねる。移すと /Applications にコピー（DMG 以外からなら移動）し、同じ名前の古いものはゴミ箱へ移し、自分が終わったあとに新しい場所で開き直して DMG を取り出す。「今後確認しない」も選べる。開発用の Debug ビルドでは尋ねない
  - 確認：試験用の DMG で、移す先を一時フォルダに差し替えて自動で「移動」を選ばせ、コピー・署名の有効さ・開き直し・DMG の取り出しを確かめた。尋ねる画面と DMG のウィンドウも撮って確かめた。ユニットテストは 135 件
  - 0.3.0 → 0.3.1（ビルド番号は 3 → 4）として、署名・公証した DMG を LP に公開した
- 追加 `scripts/dmg/make-background.swift`、`scripts/dmg/background.png`、`scripts/dmg/background@2x.png`、`scripts/dmg/layout.applescript` — DMG の背景と配置
- 変更 `scripts/release.sh` — DMG を背景と配置つきで作る
- 追加 `Macorn/App/AppMover.swift`、`MacornTests/AppMoverTests.swift`、変更 `Macorn/App/AppDelegate.swift`、`Macorn/Model/Preferences.swift` — 「アプリケーション」への移動
- 変更 `Macorn.xcodeproj/project.pbxproj` — 0.3.1（ビルド 4）
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.1 の DMG・表記・最新版の情報
- 変更 `README.md`、`AGENTS.md`、`docs/REQUIREMENTS.md` — 手順と前提

### Macorn：バージョン 0.3.0 を LP で公開する

- **きっかけ**：konta の依頼「アップデートの確認をコミットし、バージョンを 0.3.0 に上げて DMG を作り直し、LP に公開して」
- **意図・方針**
  - アップデートの確認を入れた版を早めに配り、これ以降の版を利用者に知らせられるようにする（0.2.0 以前には確認の仕組みがない）
  - 0.2.0 → 0.3.0（ビルド番号は 2 → 3）。`scripts/release.sh --publish` で署名・公証した DMG・LP の表記・`version.json` をまとめて差し替えた
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.3.0、`CURRENT_PROJECT_VERSION` を 3 に
- 変更 `site/download/Macorn.dmg`、`site/index.html`、`site/version.json` — 0.3.0 の DMG・表記・最新版の情報

### Macorn：新しいバージョンを知らせる（アップデートの確認）

- **きっかけ**：konta の質問「アプリを更新するときはどうなるか。ユーザーが確認することはできないのか」→ 選択「外部ライブラリなしで、起動時とメニューの『アップデートを確認…』で新しい版を知らせる仕組みを作って。入れ替えは手動で構わない」
- **意図・方針**
  - 前提の変更：要件定義書 9.4 の「Sparkle による自動アップデート」をやめた。外部ライブラリなしの前提を守り、知らせるところまでを自前で作る
  - LP に最新版の情報 `site/version.json`（バージョン・ビルド番号・DMG の URL）を置き、アプリはそれを読んで今の版と比べる。バージョンは数字ごとに比べる（0.10.0 は 0.9.0 より新しい）。`version.json` は `scripts/release.sh --publish` が DMG と一緒に書き直す。古い情報を読まないようキャッシュさせない
  - 起動時は、新しい版があるときだけ知らせる（失敗は黙る）。「ダウンロード」（ブラウザで DMG を開く）・「あとで」・「このバージョンをスキップ」を選べる。メニューの「アップデートを確認…」は、最新のとき・失敗したときも結果を出し、スキップした版も知らせる
  - 起動時の確認は設定の「一般 › アップデート」でオフにできる。お使いのバージョンと「今すぐ確認」も置いた
  - テストと自動操作の起動では確かめない。開発用に確かめる先を環境変数 `MACORN_UPDATE_URL` で差し替えられる
  - 確認：ユニットテスト（バージョンの比べ方、新しい版・同じ版・読めない情報）と、自動操作で「新しい版あり」「最新」「失敗（404）」の3つのアラートを撮って確かめた
  - すでに配った 0.2.0 にはこの仕組みがないので、0.2.0 の利用者には知らせられない。この仕組みが働くのは、これを入れた版から
- 追加 `Macorn/App/UpdateChecker.swift`、`MacornTests/UpdateCheckerTests.swift`、`site/version.json`
- 変更 `Macorn/App/AppDelegate.swift`、`Macorn/App/MainMenu.swift`、`Macorn/Model/Preferences.swift`、`Macorn/Settings/SettingsView.swift` — 起動時の確認、メニュー、設定
- 変更 `Macorn/App/DebugAutomation.swift` — 手順 `updatecheck:<URL>` を追加
- 変更 `scripts/release.sh`、`site/vercel.json` — `version.json` を書き、キャッシュさせない
- 変更 `README.md`、`AGENTS.md`、`docs/REQUIREMENTS.md` — 使い方と前提（テストは 129 件）

### Macorn：バージョン 0.2.0 を LP で公開する

- **きっかけ**：konta の依頼「この機能（『Finder に表示』の切り替え）を入れた DMG を作り直して、LP に公開して。バージョンも上げて」
- **意図・方針**
  - 機能を足したので 0.1.0 → 0.2.0 にした（ビルド番号は 1 → 2）
  - `scripts/release.sh --publish` で署名・公証した DMG を作り、`site/download/Macorn.dmg` と LP のバージョン・サイズの表記を差し替えた。main への push で GitHub Actions が LP ごと公開する
- 変更 `Macorn.xcodeproj/project.pbxproj` — `MARKETING_VERSION` を 0.2.0、`CURRENT_PROJECT_VERSION` を 2 に
- 変更 `site/download/Macorn.dmg`、`site/index.html` — 0.2.0 の DMG と表記

### Macorn：ほかのアプリの「Finder に表示」を Macorn で開けるようにする

- **きっかけ**：konta の質問「ファイルを開くときなどのデフォルトのアプリとして指定できないのか」→ 依頼「フォルダの既定のアプリと『Finder に表示』の行き先を Macorn にできるよう、設定に切り替えを追加して。ファイルの種類は対象外で」
- **意図・方針**
  - 「Finder に表示」：macOS 全体の設定 `NSFileViewer` に Macorn のバンドル ID を書く切り替えを、設定の「連携」に置いた。オフで設定を消して Finder に戻す。値は Macorn に保存せず、毎回 macOS から読み直す
  - 試したところ、この設定でほかのアプリから届くのは Finder 用の「項目を表示」ではなく、ふつうの「開く」要求だった。そのため専用の受け口は作らず、既存の `application(_:open:)` で受ける。同じフォルダのファイルは1つのタブにまとめて全部を選ぶよう直した（これまでは1つずつタブが開いていた）。フォルダはその中を開く
  - ほかのアプリから開いたとき、Macorn が裏にいると新しいタブがすぐキーにならず、選択が別のウィンドウに付くことがあった。開いたタブを直接使うようにした
  - フォルダの既定のアプリ：macOS 26.7 では `public.folder` の既定のアプリを変えられなかった（`NSWorkspace.setDefaultApplication` も `LSSetDefaultRoleHandlerForContentType` も paramErr。Finder に書き戻すのも同じで、テキストなどふつうの種類は変えられる）。切り替えは作らず、設定に「macOS が Finder 以外に変えられないようにしている」と書いた
  - Info.plist にはフォルダを開けるアプリとしての申告（`CFBundleDocumentTypes`、`public.folder`）だけ残した。`GENERATE_INFOPLIST_FILE` のまま、足りない項目だけを `Macorn-Info.plist` に書いて合わせる
  - 確認：別のバンドル ID の試験用のコピーで、「Finder に表示」（`NSWorkspace.activateFileViewerSelecting`）がファイルを選び、同じフォルダの2つを1つのタブにまとめることを確かめた。設定の切り替えで `NSFileViewer` が書かれ、オフで消えることも確かめ、最後に消えていることを確認した。利用者の環境の設定は元のまま
- 追加 `Macorn/Integration/SystemFileViewer.swift` — 「Finder に表示」の行き先の読み書き
- 追加 `Macorn-Info.plist`、変更 `Macorn.xcodeproj/project.pbxproj` — フォルダを開けるアプリとしての申告
- 変更 `Macorn/Settings/SettingsView.swift` — 「連携」に「Finder の代わりに使う」
- 変更 `Macorn/App/AppDelegate.swift`、`Macorn/Browser/FileBrowserViewController.swift` — ほかのアプリから開いたときのまとめ方と選択
- 変更 `Macorn/App/DebugAutomation.swift` — 手順 `windows`（全ウィンドウのフォルダと選択）、`settings` / `snapsettings` / `closesettings`、`fileviewer:on|off` を追加
- 変更 `README.md`、`AGENTS.md`、`docs/REQUIREMENTS.md` — 使い方と前提（テストの件数も 124 件に直した）

### Macorn：LP から DMG をダウンロードできるようにする

- **きっかけ**：konta の判断「一旦申請は不要なので、LP から公開する方針でお願いします」（App Store への申請状況を聞かれ、前提どおり直接配布だと答えたあと）
- **意図・方針**
  - リポジトリが非公開なので、GitHub Releases に置いても外の人はダウンロードできない。DMG は LP と同じ Vercel の `site/download/Macorn.dmg` に置く（約 3MB なので git に入れてよいと判断）
  - URL はバージョンによらず `/download/Macorn.dmg` に固定し、差し替えても LP のリンクを変えずに済むようにした。ブラウザが古い DMG を使い回さないよう、キャッシュはさせず、ダウンロードとして保存させる
  - LP の「近日公開」の表記をやめ、ヒーローの主ボタンを「ダウンロード」にした（「機能を見る」は外し、「動画で見る」を2番目に）。末尾の入手の欄は、ダウンロードのボタン・バージョンとサイズ・対応環境・入れ方の3手順にした
  - 新しい版を出すときは `scripts/release.sh --publish` で DMG と LP のバージョン・サイズの表記をまとめて差し替え、main に push すれば GitHub Actions が公開する。公証していない DMG は載せられないようにした
  - 手元の LP で、PC とスマホの幅の表示と、DMG が取れること（2,868,856 バイト）を確かめた
- 追加 `site/download/Macorn.dmg` — 配布する DMG（0.1.0）
- 変更 `site/index.html`、`site/style.css` — ダウンロードのボタンと入手の欄
- 変更 `site/vercel.json` — `/download/` をダウンロードとして返し、キャッシュさせない
- 変更 `scripts/release.sh` — `--publish` で LP の DMG と表記を差し替える
- 変更 `README.md`、`AGENTS.md`、`docs/REQUIREMENTS.md` — LP から配る方針と手順（前提：GitHub Releases ではなく LP から配る）

### Macorn：配布用の DMG を Developer ID 署名・公証つきで作る

- **きっかけ**：konta の質問「App Store に申請できるという理解で合っているか」。前提（9.4）どおり App Store ではなく直接配布だと答えたところ、「Developer の登録は済んでいるので確認してほしい」。konta が Developer ID の証明書を作り、公証の資格情報（`macorn-notary`）を登録した
- **意図・方針**
  - Xcode には有料の個人チームが2つある。証明書は「TAKUMI KON」（`Q9Q29NW29B`）で作られたので、署名も公証もこのチームにそろえた
  - 普段の開発ビルドは簡易署名（`-`）のまま残し、プロジェクトの設定は変えない。配布用のスクリプトの中でだけ、署名の設定を Developer ID に上書きする（証明書のない環境でも開発ビルドが通るように）
  - 手順：Release ビルド（Hardened Runtime・タイムスタンプつきの署名）→ DMG（アプリと「アプリケーション」への近道）→ DMG に署名 → 公証 → 結果を DMG に添付 → Gatekeeper で判定
  - 公証のパスワードはキーチェーンにあり、スクリプトはプロファイル名だけを使う
  - 実際に `Macorn-0.1.0.dmg`（Intel と Apple シリコンの両方で動く）を作った。公証は Accepted で、DMG と、そこから取り出したアプリ（ダウンロード扱いの印を付けたもの）の両方が Gatekeeper で「Notarized Developer ID」と判定された
  - Sparkle による自動アップデートと GitHub Releases での配布は、まだ手を付けていない
- 追加 `scripts/release.sh` — 配布用の DMG を作る
- 変更 `README.md`、`AGENTS.md`、`docs/REQUIREMENTS.md` — 配布の手順と、9.4 の実装状況

### Macorn：LP の自動デプロイ（CD）を GitHub Actions で行う

- **きっかけ**：konta の依頼「Vercel との連携も確認してほしい。CD 含めて」。確認の途中で「これを元にして、GitHub Actions に設定してほしい」（Qiita「Vercel × GitHub Actions」の記事）
- **意図・方針**
  - 確認すると、Vercel のプロジェクト `macorn` は GitHub とつながっておらず、CLI から直接デプロイしていた。konta が `vercel git connect` で `takumi8420/Macorn` とつないだ
  - 記事のやり方に合わせ、デプロイは GitHub Actions から Vercel の CLI で行う（`vercel pull` → `vercel build` → `vercel deploy --prebuilt`）。main への push は本番、ほかのブランチはプレビュー
  - CLI は `site/` の中で動かすので、Vercel のルートディレクトリは `.` のままでよい（変更しない）
  - `site/` に変更があるときだけ動かす（paths の指定）。アプリのコードだけの push では LP を作り直さない。本番は手動でも動かせる
  - Vercel 側の Git 連携による自動デプロイは、`vercel.json`（リポジトリ直下と `site/`）の `git.deploymentEnabled: false` で止め、二重に公開しない
  - Vercel のトークン・チームの ID・プロジェクトの ID は、記事どおり GitHub の Secrets（`VERCEL_TOKEN`・`VERCEL_ORG_ID`・`VERCEL_PROJECT_ID`）に置く。konta が登録した（Claude はトークンの値を扱わない）
  - 記事と違う点：`actions/checkout`・`actions/setup-node` は最新の v7 にし（v4 は Node.js 20 の廃止の警告が出た）、Node.js 22 を明示した。デプロイした URL を実行結果の概要に出す
  - 初回の実行で本番が 404 になった。原因は2つ。(1) Git 連携をつないだ時点で、Vercel がリポジトリの直下（`index.html` がない）を本番にデプロイしていた。(2) GitHub Actions のビルド結果（`--prebuilt`）では、`cleanUrls` の指定があるとトップページが見つからなくなる。手元の CLI でつくった正常なデプロイを本番に戻してから、`site/vercel.json` の `cleanUrls` を外した（LP は1ページなので不要）。手元で同じ手順のプレビューをつくり、トップページ・CSS・画像が出ることを確かめた
  - 動作の確認（konta の依頼「その確認もそちらで試してほしい」）：使い捨てのブランチ `test/cd-check` で、`site/` を変えない push ではワークフローが動かないこと、`site/` を変える push ではプレビューが作られ（本番は変わらない）中身も反映されることを確かめ、ブランチは消した。main への push で本番に公開されることは前の push で確かめた。`site/` を変えない main への push で本番が動かないことは、この記録の push で確かめる
- 追加 `.github/workflows/vercel-production.yml`、`.github/workflows/vercel-preview.yml` — 本番とプレビューのデプロイ
- 追加 `vercel.json`、変更 `site/vercel.json` — Vercel の Git 連携による自動デプロイを止める。`cleanUrls` を外す
- 変更 `AGENTS.md`、`README.md` — 公開のしかた

### Macorn：GitHub のリモートを追加して push する

- **きっかけ**：konta の依頼（`git remote add origin git@github.com:takumi8420/Macorn.git` → `git branch -M main` → `git push -u origin main`）
- **意図・方針**：指示どおり `origin` を追加し、`main` を push した。push の前に、環境変数や Vercel の紐付けのファイルが履歴に入っていないことを確かめた。LP の Vercel は引き続き CLI から直接デプロイする（GitHub とは連携していない）
- 変更 `AGENTS.md` — 関連リンクにリモートリポジトリを追加

### Macorn：LP のボタンと画面写真の間を空け、動画からバージョンの表記を外す

- **きっかけ**：konta の指摘（スクリーンショットつき）「ここに余白がないのでブラッシュアップしてほしい」「動画において、mac のバージョン指定はしないでおいてください。デモが見れればいいので変に情報を載せないでほしい」
- **意図・方針**
  - LP のヒーローで、ボタンのすぐ下に画面写真がくっついていた。画面写真の上の余白を、あとに書いた共通の `.shot { margin: 0 }` が打ち消していたため。指定を強くして、ボタンとの間を 56〜88px（画面の幅による）空けた
  - 動画の締めは「近日公開 · macOS 15 以降」をやめ、ロゴだけにした。動画はデモを見せるものとし、対応バージョンや公開時期のような情報は載せない
- 変更 `site/style.css` — ヒーローの画面写真の上の余白
- 変更 `promo/video/src/Flow.tsx`、`promo/video/README.md` — 締めをロゴだけに
- 変更 `site/assets/macorn-promo.mp4`、`site/assets/video-poster.jpg` — 書き出し直した動画

### Macorn：LP の余白とレイアウトを整える

- **きっかけ**：konta の依頼「LP の余白などのレイアウトをブラッシュアップしてほしい」
- **意図・方針**
  - 余白を段階（セクションの上下・見出しから中身・機能の行どうし・左右）に分けて変数にし、画面の幅に合わせて伸び縮みさせた。セクションごとにばらばらだった間隔をそろえた
  - 日本語が「紹介し／ます」「ではな／く」のように語の途中で折り返していたので、文節の切れ目で折り返すようにし（`word-break: auto-phrase`）、見出しは行の長さをそろえた
  - 動画・機能・ショートカットの各セクションに、英字のラベル・見出し・説明の3段の見出しを付けた
  - 機能の6つの行に番号（01〜06）を付け、文の幅を読みやすい長さにした。そのほかの機能のカードは 4＋2 の並びから 3×2 にした
  - ヒーローの説明とボタン・画面写真の間、3つの軸のカードの内側の余白を広げた
  - PC（1440px）とスマートフォン（375px）の幅で確かめてから、本番に公開し直した
- 変更 `site/index.html` — セクションの見出し、機能の番号、締めの文の分け方
- 変更 `site/style.css` — 余白の段階、折り返し、各セクションの間隔とカード

### Macorn：LP を Vercel に公開する

- **きっかけ**：konta の依頼「LP に関して Vercel にデプロイできますか？」。公開範囲は「本番に公開」、チームは「Vercel CLI で再度確認して」との回答で、確認すると CLI のログインが個人のアカウントに切り替わっていたため、そのチーム「konta's projects」に置いた
- **意図・方針**
  - Git のリモートがないので、Git 連携ではなく CLI から `site/` を直接デプロイする。プロジェクト `macorn` を新しく作り、本番の URL は https://macorn.vercel.app
  - 公開後、ページ・動画・画像がすべて読み込めることを確かめた
  - SNS で共有されたときの画像（og:image）は、相対パスだと読まれないことがあるので、完全な URL にした。正規の URL（canonical・og:url）も入れた
  - CLI が作った `.vercel`（プロジェクトとの紐付け）と `.env.local` は、`site/.gitignore` で Git に入れない
- 変更 `site/index.html` — og:image を完全な URL に、og:url と canonical を追加
- 追加 `site/.gitignore` — Vercel の紐付けと環境変数のファイルを除く（CLI が作成）
- 変更 `AGENTS.md`、`README.md` — 公開先と公開し直す方法

## 2026-10-26

### Macorn：紹介動画と LP を作る

- **きっかけ**：konta の依頼「~/.claude に登録されている create-demo-video をもとにプロモーション動画を作成してほしい」「LP の作成もお願いします。公開は Vercel を想定」。確認した結果、タイトルと締めの画面を入れる／見せる機能は2画面・コマンドパレット・タグとサイドバー・プレビュー・ターミナルとエディタ連携の全部／映すフォルダは架空のサンプルを用意する、とした
- **意図・方針**
  - create-demo-video は Web アプリ向け（ヘッドレス Chrome で撮る）なので、Macorn では Debug ビルドの自動操作で画面を作り、合図ごとにウィンドウを撮る形にした（`promo/capture/capture.py`）。ウィンドウは 1280×720 で撮って 1920×1080 にする。利用者のキー入力を奪わず、別のデスクトップにあっても撮れる
  - 見えていないデスクトップのウィンドウを撮ると、Web の表示（Markdown のプレビュー）が空になり、パレット・ポップオーバーは後ろまで写る。これらはアプリが自分で描いた画像を重ねる。パレットを開いている間は本体も撮れないことがあるので、開く前に下地を撮っておく
  - 実在の顧客名や個人のフォルダを映さないよう、`/Users/Shared/MacornDemo` に架空の開発プロジェクト一式を作るスクリプトを用意した（`promo/sample/make-sample.sh`）
  - 撮影では、設定・タグ・履歴に普段とは別の保存先を使う。アクセントの色はブランドのリスの色、外観はダーク
  - 動画は Remotion（スキルのひな形）で、タイトル → 6場面 → 締めの約 72 秒。色はブランドの紺・クリーム・オレンジにした
  - LP は Vercel にそのまま置ける静的な HTML と CSS（`site/`）。画面写真・動画・SNS 用の画像は `promo/build-site-assets.sh` で作る。配布方法はまだ決まっていないので「近日公開」とした。公開（Vercel への配置）は行っていない
- 追加 `promo/sample/make-sample.sh`、`promo/capture/`（撮影スクリプトと手順）、`promo/video/`（Remotion のプロジェクト）、`promo/build-site-assets.sh` — 撮影・動画・LP 用の画像
- 追加 `site/` — LP（`index.html`・`style.css`・`vercel.json`・`assets/`）。PC とスマートフォンの幅で表示を確かめた
- 追加 `.claude/launch.json` — LP を手元で見るためのサーバー（python3 -m http.server）
- 変更 `.gitignore` — Remotion の node_modules と書き出しを除く
- 変更 `AGENTS.md`、`README.md` — フォルダ構成、紹介動画と LP の作り方

### Macorn：撮影の準備で見つかった不具合を直し、自動操作が普段の設定を使わないようにする

- **きっかけ**：紹介動画の撮影の準備（上の作業）で見つかったもの
- **意図・方針**
  - プレビューを閉じたあと、一覧の上に境目の線が残っていた。閉じるときはプレビューを分割から外すようにした
  - 別のフォルダへ移っても、前のフォルダのファイルのプレビューが出たままだった。移ったときにプレビューを更新する
  - TypeScript（.ts）のファイルを、拡張子が同じ動画（MPEG-2 TS）としてプレビューしていた。.ts・.tsx などはプレビューしない
  - タグの列で、タグが多いと2行に折り返していた。1行に収め、はみ出したら末尾を省略する
  - 自動操作（MACORN_DEBUG_STEPS）が、終了時に利用者の前回のウィンドウを上書きし、起動時にも前回のウィンドウを開いていた。自動操作では前回のウィンドウを開かず、保存もしない
  - MACORN_DEFAULTS_SUITE を指定した自動操作では、サイドバーだけでなく表示の設定（プレビュー・テーマ・列など）も別の保存先を使う（`AppDefaults`）
  - 撮影用の手順を足した（winsize・shot・closepopover・splitinfo）
- 追加 `Macorn/App/AppDefaults.swift` — 設定の保存先
- 変更 `Macorn/Browser/FileBrowserViewController.swift`、`FileBrowserViewController+Preview.swift` — プレビューの境目の線、移ったときのプレビュー
- 変更 `Macorn/Preview/FilePreviewController.swift` — .ts をプレビューしない、撮影用に Web の表示を返す
- 変更 `Macorn/Browser/FileCellView.swift` — タグの列を1行に
- 変更 `Macorn/App/AppDelegate.swift` — 自動操作では前回のウィンドウを開かず、保存もしない
- 変更 `Macorn/Model/Preferences.swift`、`Macorn/Settings/Theme.swift`・`SettingsView.swift`・`ShortcutStore.swift`、`Macorn/Sidebar/SidebarStore.swift`・`SidebarViewController.swift`、`Macorn/Palette/PaletteModel.swift`、`Macorn/Window/BrowserWindowController.swift` — 設定の保存先を `AppDefaults` に
- 変更 `Macorn/App/DebugAutomation.swift` — 撮影用の手順
- 変更 `MacornTests/MarkdownRendererTests.swift` — .ts をプレビューしないテスト（合計 124 件）

### Macorn：お気に入り・セクションに置いたタグは、一番下の階層の名前だけを出す

- **きっかけ**：konta の指摘（スクリーンショットつき）「セクション化のタグが二重でセクション表示されていて不自然。"会社A/" の部分は不要」。「会社A」というセクションの中に「会社A/案件A」と出ていた
- **意図・方針**：お気に入り・自分で作ったセクションに置いたタグの行は、「タグ」の一覧と同じく一番下の階層の名前（「案件A」）だけを出す。階層を含む名前はマウスを乗せたときの説明に出す。表示名を自分で付けた場合はそちらを優先する
- 変更 `Macorn/Sidebar/SidebarViewController.swift` — 置いたタグの行の名前と説明

### Macorn：タグの並び順をドラッグで変えられるようにする

- **きっかけ**：konta の指摘「タグなどの並び順を入れ替えられない」
- **意図・方針**
  - 原因：「タグ」の一覧はいつも名前の順で、行の間へのドロップは「いちばん上の階層へ移す」としか扱っていなかった
  - タグの並び順を利用者が決めるものにした。保存ファイルのタグの並びをそのまま順番として使い、同じ親の下ではこの順に並べる。以前のファイルは、今まで見えていた名前の順を最初の並び順にする
  - サイドバーでは、タグの行の真ん中へ置くとその下の階層へ（今までどおり）、行の上下の端（行の間）へ置くとその位置へ入る。ほかの親の下の行の間へ置けば、親も変わる
  - 右クリックの「タグ」・タグの編集・「親のタグ」のメニューも同じ順に並ぶ。「タグ別」の並べ替えとフォルダの色も、名前の順ではなくこの順で最初のタグを基準にした
  - お気に入り・自分で作ったセクションの中の並べ替えは、行の端へのドロップで動くことを確かめた
- 変更 `Macorn/Model/TagStore.swift` — 並び順を保存して使う、指定の位置へ動かす、以前のファイルは名前の順で始める、「タグ別」の基準を並び順に
- 変更 `Macorn/Sidebar/SidebarViewController.swift` — 「タグ」の中の行の間へのドロップで並べ替え・親の変更
- 変更 `MacornTests/TagTests.swift` — 並び順のテスト（合計 124 件）
- 変更 `AGENTS.md`、`README.md`、`docs/REQUIREMENTS.md` — 確定している前提、操作一覧、S-07 の内容

### Macorn：子のタグが付いていれば、親のタグも付いているとみなす

- **きっかけ**：konta の指摘「既存のタグの子アイテムに移動したがフォルダの属性にタグが追加されておらず、表面上と実態に乖離が起こっている」。実際のタグのデータを見ると、「案件B」などを「会社A」の下へ移したあと、サイドバーの「会社A」の件数・一覧には子のタグの項目が入る一方、フォルダには「会社A/案件B」だけが付き、一覧のタグの列には「案件B」としか出ていなかった
- **意図・方針**
  - 2つの案（親のタグも付いているとみなす／実際に親のタグも付けて保存する）から、konta の選択で「みなす」にした。保存は実際に付けたタグだけなので、タグを移したり外したりしても親とずれない
  - 一覧のタグの列・右クリックの「タグ」・タグの編集では、親のタグも付いているものとして出す（列は「● 会社A ● 案件B」）
  - 親のタグを外すと子のタグも外す（親だけ外しても、子が残る限り親も付いているとみなされてしまうため）
  - フォルダの色分けと「タグ別」の並べ替えは、実際に付けたタグ（いちばん細かい分類）のままにした。親の色にそろうと、子のタグの見分けが付かなくなるため
- 変更 `Macorn/Model/TagStore.swift` — 付いているタグに親を含める、実際に付けたタグだけを引く、外すときに子も外す、色分け・並べ替えは実際に付けたタグで
- 変更 `MacornTests/TagTests.swift` — 親のタグをみなすテスト（合計 122 件）
- 変更 `AGENTS.md`、`docs/REQUIREMENTS.md` — 確定している前提、S-07 の内容

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
