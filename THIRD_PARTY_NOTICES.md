# サードパーティのライセンス表記

このアプリに同梱している素材と、その利用条件。
Android版の [THIRD_PARTY_NOTICES.md](../../AndroidStudioProjects/Stash/THIRD_PARTY_NOTICES.md)
と同じ素材を使っている。

## フォント（`Pokke/Fonts/`）

すべて [Google Fonts](https://fonts.google.com/) から取得した
**SIL Open Font License 1.1**（https://scripts.sil.org/OFL）のフォント。
OFLは埋め込み・再配布を許可しており、表記義務のみがある。

| ファイル | 書体 | 作者 |
|---|---|---|
| `caprasimo_regular.ttf` | Caprasimo | Eben Sorkin, Mirko Velimirović |
| `figtree_regular/medium/semibold/bold.ttf` | Figtree | Erik Kennedy |
| `zen_maru_gothic_regular/bold.ttf` | Zen Maru Gothic | Yoshimichi Ohira |

**Zen Maru Gothicは1ウェイトあたり約3.8MB**（和文の字数ぶん）で、
アプリの大きさの大半を占めている。減らしたくなった場合の選択肢:

- 使う字だけに絞ったサブセットを作る
- 和文をシステムの書体に任せる（丸ゴシックの印象は失われる）

英数はFigtree、和文はZen Maru Gothic——という組み合わせは
`Pokke/UI/Fonts.swift` の `kCTFontCascadeListAttribute` で実現している。

## アイコン

- **Lucide**（https://lucide.dev / ISC License） — `Pokke/UI/LucideIcons.swift`。
  ライブラリではなく、使うぶんだけパスデータを写している。
  パス文字列の解釈は `PokkeCore/SVGPath.swift`
- **Googleロゴ** — `Pokke/UI/GoogleLogo.swift`。
  [Google ブランドの使用ガイドライン](https://developers.google.com/identity/branding-guidelines)
  に従い、色・形を変えずにログインボタンでのみ使用する

## サービスのロゴ

一覧のサムネイルが取れなかったときに、Googleのファビコンサービス
（`https://www.google.com/s2/favicons`）からブランドのアイコンを取得している。
ドメイン名を外部へ送るため、プライバシーポリシーにもその旨を書いてある。
