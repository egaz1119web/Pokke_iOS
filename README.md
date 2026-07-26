# Pokke (iOS)

Android版 [`Stash`](../../AndroidStudioProjects/Stash) の iOS 移植。仕様は Android に合わせてある。

```bash
open /Users/egaz/iOS/Pokke/Pokke.xcodeproj
```

## 構成

| ディレクトリ | 中身 | 所属ターゲット |
| --- | --- | --- |
| `PokkeCore/` | モデル・JSON・マージ・OGP取得・リポジトリ（純粋なロジック） | Pokke / PokkeShare / PokkeTests |
| `Pokke/` | SwiftUIの画面、Firebase、AdMob、アプリのエントリポイント | Pokke |
| `PokkeShare/` | 共有シート拡張（Androidの `ShareReceiverActivity` 相当） | PokkeShare |
| `PokkeTests/` | ユニットテスト（Androidの `app/src/test` から移植、34件） | PokkeTests |

- Bundle ID: `com.egaz.stash`（Androidの applicationId と同じ）／拡張は `com.egaz.stash.Share`
- App Group: `group.com.egaz.stash` — 共有拡張とアプリ本体が `stash.json` を共有するのに必要
- 最低iOS: 17.0 / Swift 5 / チーム `W2MGTX4423`

### Androidとの対応

| Android | iOS |
| --- | --- |
| `data/Models.kt` `StashJson.kt` `StashMerge.kt` `TodayPick.kt` `DomainGrouping.kt` `MetadataFetcher.kt` | `PokkeCore/` に同名で1対1移植 |
| `StashRepository`（`filesDir/stash.json`） | `StashRepository` + `StashStore`（App Groupの `stash.json`） |
| `GoogleAuth`（GoogleSignInClient + Firebase Auth） | `GoogleAuth`（GoogleSignIn-iOS + Firebase Auth） |
| `FirestoreSync` | `FirestoreSync`（**同じ `users/{uid}` ドキュメント・同じJSON**） |
| `AdsConsent`（UMP） | `AdsConsent`（UMP） |
| `res/values/strings.xml` + `values-ja` | `Localizable.xcstrings`（キー名はAndroidと同一） |
| `ShareReceiverActivity` | `PokkeShare`（Share Extension） |

**JSONスキーマはAndroidと完全に同一**（キー名・エポックミリ秒）。同じGoogleアカウントで
ログインすればAndroid端末とiPhoneの間でそのまま同期される。`PokkeTests` に
「Android版が書いたJSONを読める」ことの回帰テストを入れてある。

### iOSで変えたところ

- **タブアイコン**: Androidは絵文字だが、iOSのタブバーはSF Symbolsが標準の見え方なのでそちらに合わせた
- **共有拡張はOGPを取らない**: iOSの拡張は別プロセスで短命なため、拡張はURLの保存だけ行い、
  アプリ本体がフォアグラウンド復帰時に `reloadFromDisk()` → `backfillMetadata()` で
  タイトル・サムネを埋める（`RootView` の `scenePhase` 監視）
- **配色はライト固定**: Android版が `lightColorScheme` 固定なので、`preferredColorScheme(.light)` で揃えた

---

## Googleログイン / クラウド同期 ✅ 設定済み

- `Pokke/GoogleService-Info.plist`（Bundle ID `com.egaz.stash` / プロジェクト `pokke-600ea` — Androidと同一）
- `Pokke/Info.plist` の `CFBundleURLSchemes` に `REVERSED_CLIENT_ID` を登録済み
- 設定画面のログインボタンが有効になり、Googleの認証フローが起動するところまで確認済み

**plist の置き場所は `Pokke/Pokke/GoogleService-Info.plist`**（アプリのソースフォルダの中）。
プロジェクト直下に置くと同期グループの外なのでバンドルに入らず、`FirebaseApp.configure()` が
走らないまま「設定が未完了です」の表示になる。差し替える時は場所に注意。

Firebase Console 側で残っている確認事項:

- [ ] Authentication → Sign-in method で **Google が有効**か（Android と共用なので済んでいるはず）
- [ ] Firestore ルールが [`firestore.rules`](../../AndroidStudioProjects/Stash/firestore.rules) の内容で公開されているか

SHA-1 の登録は Android 固有なので iOS 側では不要。
同期先は Android と同じ `users/{uid}` ドキュメントなので、同じアカウントでログインすれば
Android で保存したリンクがそのまま出てくる。

## AdMob ✅ iOS用アプリ設定済み

- アプリID: `Pokke/Info.plist` の `GADApplicationIdentifier` = `ca-app-pub-9758850573913500~4992835164`
- ネイティブ広告ユニットID（Release）: `Pokke/UI/NativeAdCard.swift` の `AdUnits.native` = `ca-app-pub-9758850573913500/1496589070`
- Debugビルドは引き続きGoogle公式テストIDのまま（Android版と同じ方針。本番IDでのDebug実行は厳禁）

アプリIDはビルド構成で出し分けられないため常に本番値だが、これは問題ない。安全性は
「どの広告ユニットIDでリクエストするか」で決まり、そちらはDebug/Releaseで切り替えている
（本番アプリID＋テスト広告ユニットIDの組み合わせがGoogle公式の開発時テスト方法）。

- [ ] AdMob Console の GDPR メッセージ（プライバシーとメッセージ）に iOS アプリを追加したか確認する
      — Android の [RELEASE.md](../../AndroidStudioProjects/Stash/RELEASE.md) に書いてある
      「メッセージが無いと広告が1件も出ない」の件は iOS でも同じ

同意フォームの出方を検証したい時は `Pokke/Data/AdsConsent.swift` の
`forceEeaInDebug` を `true` にすると、DEBUGビルドでEEA地域が強制されてフォームが出る。

## 未対応（コンソール側の作業が要るもの）

### 1. App Store 提出前

- [ ] アプリアイコン — Androidのアダプティブアイコン（432px）を合成・拡大したもので暫定。
      1024pxで書き出し直すのが望ましい（`Pokke/Assets.xcassets/AppIcon.appiconset/`）
- [ ] `Info.plist` に `SKAdNetworkItems`（AdMobが配布しているリストを貼る）
- [ ] プライバシーマニフェスト `PrivacyInfo.xcprivacy` — 広告IDとユーザーデータを扱うので必須
- [ ] App Privacy（データ収集の申告）— Play の データセーフティ と同じ内容
- [ ] 共有拡張の表示名 `Save to Pokke` を日本語化したい場合は
      `PokkeShare/` に `InfoPlist.xcstrings` を追加する

---

## コマンド

```bash
xcodebuild test -project Pokke.xcodeproj -scheme PokkeTests -destination 'platform=iOS Simulator,name=iPhone 17'
```

```bash
xcodebuild build -project Pokke.xcodeproj -scheme Pokke -destination 'platform=iOS Simulator,name=iPhone 17'
```
# Pokke_iOS
