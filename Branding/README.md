# Macorn ブランドアセット

Macorn（マコーン）は Mac + Acorn（どんぐり）から生まれた名前です。リスがどんぐりを大事に抱えるように、ファイルをしまって、すぐ取り出せるファイルマネージャーを表しています。

アイコンは円・半円・三角だけで組んだ幾何的なリスが、どんぐりを両手で抱えるデザイン（ナチュラル案）です。

## フォルダ構成

```
Branding/
├── AppIcon/
│   ├── macorn-icon.svg          マスター（1024px、macOS アイコングリッド準拠）
│   ├── Macorn.icns              アプリ用アイコン（16〜1024px 全サイズ入り）
│   ├── AppIcon.appiconset/      Xcode のアセットカタログ用（Contents.json 付き）
│   └── png/                     各サイズの PNG（16 / 32 / 64 / 128 / 256 / 512 / 1024）
└── Logo/
    ├── macorn-logo-light.svg/.png   明るい背景用（アイコン + ワードマーク）
    ├── macorn-logo-dark.svg/.png    暗い背景用
    └── macorn-wordmark.svg          文字のみ
```

ロゴの SVG は文字をアウトライン化してあるので、フォントがない環境でも同じ見た目で表示できます。

## Xcode への組み込み

1. Xcode で `Assets.xcassets` を作成します（File › New › File… › Asset Catalog）。
2. `AppIcon.appiconset` フォルダをそのまま `Assets.xcassets` の中にコピーします。
3. ターゲットの General › App Icons で `AppIcon` を選びます。

アセットカタログを使わない場合は、`Macorn.icns` をバンドルの Resources に入れて、Info.plist の `CFBundleIconFile` に `Macorn` を指定します。

## カラー

| 用途 | カラー |
| --- | --- |
| 背景（クリーム） | `#F6EBD9` |
| リスの体 | `#C9773A` |
| しっぽ | `#E09A55` |
| お腹 | `#FBEBD3` |
| どんぐり（実） | `#8A5226` |
| どんぐり（帽子・軸） | `#5A3418` |
| 目・文字 | `#2A211B` |
| ダーク版の背景（ネイビー） | `#24324A` |

## フォント

- ワードマーク: Outfit SemiBold（SIL Open Font License）
- カナ表記: Zen Kaku Gothic New Regular（SIL Open Font License）
