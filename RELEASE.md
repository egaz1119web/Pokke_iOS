# App Store 提出チェックリスト（iOS）

Android版 [RELEASE.md](../../AndroidStudioProjects/Stash/RELEASE.md) のiOS版。
私（Claude）が代わりにできない工程（Apple Developer / App Store Connectへのログインが
必要なもの）だけをここに残す。コード側の準備はこのファイル作成時点で完了している。

## 済んでいること（コード側）

- [x] Firebase（Googleログイン + Firestore同期）— `Pokke/GoogleService-Info.plist` 配置済み、
      URLスキーム登録済み、認証フロー起動まで確認済み
- [x] AdMob 本番ID（アプリID・ネイティブ広告ユニットID）に差し替え済み
- [x] `SKAdNetworkItems`（Google公式50件、`developers.google.com/admob/ios/ios14` より2回取得し
      一致を確認）
- [x] `PrivacyInfo.xcprivacy`（アプリ本体分。SDK同梱分と二重にならないよう自前収集分のみ記載）
- [x] Releaseアーカイブがローカルで成功することを確認済み（署名は現状Development証明書。
      Distribution証明書は下記「1」で自動発行される）

---

## 1. Apple Developer Portal — App ID を登録する

[developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list)
→ 「+」→ **App IDs** → **App**

| 項目 | 値 |
| --- | --- |
| Description | `Pokke` |
| Bundle ID | Explicit: `com.egaz.stash` |
| Capabilities | **App Groups** にチェック |

続けて共有拡張用も登録:

| 項目 | 値 |
| --- | --- |
| Description | `Pokke Share Extension` |
| Bundle ID | Explicit: `com.egaz.stash.Share` |
| Capabilities | **App Groups** にチェック |

**App Groups** タブ（左メニュー）→「+」で `group.com.egaz.stash` を作成し、
上記2つのApp IDの両方に紐付ける。

> 上記を手動でやらなくても、Xcodeで「Automatically manage signing」が有効なら
> （このプロジェクトは既に有効）、実機ビルドやアーカイブ時にXcodeが自動で登録してくれることが多い。
> ただし **App Groupsのような明示的なCapabilityは自動登録に失敗することがある**ので、
> エラーが出たらこの手順で手動登録する。

---

## 2. 公開されたプライバシーポリシーURLを用意する ★App Store Connectの必須項目

現状 `docs/privacy-policy.html`（Android側にある、日本語のみ）は**どこにも公開されていない**。
Android版のRELEASE.mdでも積み残しになっている項目で、iOSでも同じものが必要。

- [ ] 英語版を用意する（日本語のみだとグローバル配信時に審査で指摘され得る）
- [ ] どこかでホストして公開URLにする（GitHub Pagesが手早い。例:
      `egaz1119web/Pokke` リポジトリの `docs/` を Pages で公開するなど）
- [ ] そのURLをApp Store Connectの「App Privacy」とアプリ情報の両方に設定する

---

## 3. App Store Connect — アプリレコードを作成する

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) → マイApp → 「+」→ 新規App

| 項目 | 値 |
| --- | --- |
| プラットフォーム | iOS |
| 名前 | `Pokke` （Android版のPlay掲載名は `Pokke - あとで読むリンク保存` だが、
  App Storeの30文字制限とサブタイトル欄の両方を使うなら 名前=`Pokke` / サブタイトル=
  `あとで読むリンク保存` の分割がおすすめ） |
| プライマリ言語 | 日本語 |
| バンドルID | `com.egaz.stash`（手順1で登録したものがプルダウンに出る） |
| SKU | `pokke-ios`（他と被らなければ何でもよい。あとから変更不可なので注意） |
| ユーザーアクセス | フルアクセス |

---

## 4. App Privacy（データ収集の申告）

[`Pokke/PrivacyInfo.xcprivacy`](Pokke/PrivacyInfo.xcprivacy) の内容と、Android版の
Play「データセーフティ」申告と揃えてある。ASCの質問フォームは選択式なので、以下を目安に回答する。

**「データを収集していますか？」→ はい**

| データ種別 | 収集理由 | ユーザーに紐付くか | トラッキングに使うか |
| --- | --- | --- | --- |
| メールアドレス | App機能（Googleログインでの端末間同期） | Yes | No |
| ユーザーコンテンツ（その他）＝保存したリンク・コレクション・タグ | App機能 | Yes | No |
| 識別子（デバイスID） | 分析・サードパーティ広告・開発者広告 | Yes | **Yes** |
| 位置情報（おおまかな位置情報） | 分析・サードパーティ広告・開発者広告 | Yes | No |
| 診断（クラッシュデータ・パフォーマンスデータ・その他診断データ） | 分析 | 一部Yes/一部No（下記参照） | No |
| 製品とのやり取り（広告の視聴・操作） | 分析・広告 | Yes | No |

下3つ（デバイスID・位置情報・診断）は **AdMob SDKが独自に収集するもの**
（`GoogleMobileAds.xcframework/PrivacyInfo.xcprivacy` に開発元が事前宣言済みの内容をそのまま転記）。
アプリのコードが直接集めているわけではないが、申告上は「アプリに含まれるかどうか」で聞かれるので
含める。

**トラッキングは「あり」** — AdMobのデバイスID収集がトラッキングに該当するため
（Android版でも「広告ID」を同様の理由でデータセーフティに記載済み）。ただし本アプリ自体は
ATT（App Tracking Transparency）のプロンプトを実装していないため、iOS 14.5以降は
ユーザーが個別許可しない限りIDFAは取得されず、トラッキングは実質発生しない
（プロンプトを出す設定はまだ入れていない。将来ATTを実装する場合は
`Pokke/Data/AdsConsent.swift` 周辺に追加する）。

---

## 5. アプリ対象デバイス（要確認）

現在プロジェクトは `TARGETED_DEVICE_FAMILY = "1,2"`（iPhone + iPad 両対応）になっているが、
iPadでのレイアウト確認はしていない。初回リリースは **iPhoneのみ**に絞ることを推奨。
iPad対応を外す場合は `Pokke.xcodeproj` の General → Supported Destinations で iPad を外す。

---

## 6. スクリーンショット

App Store Connectの必須サイズ:

- **6.9インチiPhone**（iPhone 17 Pro Max等）— 必須
- 13インチiPad — iPadに対応する場合のみ必須

Claudeがシミュレータで撮影したものを用意できる（後述）。実機の見た目そのままなので
加工なしでそのままアップロード可能。

---

## 7. ストア掲載文（App Store）

Android版 [`docs/store-listing.md`](../../AndroidStudioProjects/Stash/docs/store-listing.md)
の内容を流用できる。App Store固有の項目のみ差分:

| 項目 | 文字数上限 | 値 |
| --- | --- | --- |
| 名前 | 30文字 | `Pokke` |
| サブタイトル | 30文字 | `あとで読むリンク保存` (EN: `Save & Read Later`) |
| プロモーションテキスト | 170文字 | いつでも変更可。例: `気になったリンクを共有ボタンから1タップで保存。タグとコレクションであとから探せます。` |
| 説明文 | 4000文字 | Android版の「詳しい説明」をそのまま使える |
| キーワード | 100文字（カンマ区切り、スペース節約） | `あとで読む,リンク保存,ブックマーク,共有,タグ,コレクション,同期,read later,bookmark,save links` |
| サポートURL | — | 用意が必要（Play Console同様、連絡先が必要） |
| マーケティングURL | — | 任意 |

---

## 8. ビルドをApp Store Connectへアップロードする

コードの準備が整い、手順1〜3が終わったら:

1. Xcodeで `Pokke.xcodeproj` を開く（`open /Users/egaz/iOS/Pokke/Pokke.xcodeproj`）
2. スキームを `Pokke` / 実機 or `Any iOS Device` に設定
3. メニュー → Product → Archive
4. Organizerが開いたら「Distribute App」→「App Store Connect」→「Upload」
   （Automatic signingならDistribution証明書・App Store用プロビジョニングプロファイルは
   ここでXcodeが自動生成する）
5. アップロード完了後、App Store Connect側の「TestFlight」または「App Store」タブに
   ビルドが数分〜数十分で反映される

**この工程はApple IDでのサインイン・2要素認証が必要なため、Xcodeで対話的に行うのが確実。**
CLIからの `xcodebuild -exportArchive` でも可能だが、認証まわりでつまずきやすいので
初回はXcode GUIを推奨。

---

## 9. Export Compliance（暗号化に関する申告）

`Info.plist` に `ITSAppUsesNonExemptEncryption = false` を設定済み
（HTTPS標準以外の独自暗号化を行っていないため）。App Store Connectの提出フローで
この設定がそのまま使われ、追加の質問には基本的に応答不要のはず。
