# Pokke (iOS)

Android版 [`Stash`](../../AndroidStudioProjects/Stash) の iOS 移植。仕様は Android に合わせてある。

```bash
open /Users/egaz/iOS/Pokke/Pokke.xcodeproj
```

## 構成

| ディレクトリ | 中身 | 所属ターゲット |
| --- | --- | --- |
| `PokkeCore/` | モデル・JSON・マージ・OGP取得・リポジトリ（純粋なロジック） | Pokke / PokkeShare / PokkeTests |
| `Pokke/` | SwiftUIの画面、デザインシステム、Firebase、AdMob、アプリのエントリポイント | Pokke |
| `Pokke/Fonts/` | 同梱フォント（Info.plist の `UIAppFonts` に対応） | Pokke |
| `PokkeShare/` | 共有シート拡張（Androidの `ShareReceiverActivity` 相当） | PokkeShare |
| `PokkeTests/` | ユニットテスト（Androidの `app/src/test` から移植、77件） | PokkeTests |

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
| `data/AppPrefs.kt`（SharedPreferences） | `AppPrefs`（UserDefaults） |
| `data/CollectionIcons.kt` | `CollectionIcons` |
| `ui/theme/Theme.kt` `Fonts.kt` | `UI/Theme.swift` `Fonts.swift` |
| `ui/icon/LucideIcons.kt`（ImageVector） | `UI/LucideIcons.swift` ＋ `PokkeCore/SVGPath.swift` |
| `ui/Components.kt` | `UI/Components.swift` |
| `data/ImageSaver.kt`（MediaStore） | `Data/ImageSaver.swift`（Photos） |
| `res/values/strings.xml` + `values-ja` + `values-ko` | `Localizable.xcstrings`（キー名はAndroidと同一） |
| `ShareReceiverActivity` | `PokkeShare`（Share Extension） |

**JSONスキーマはAndroidと完全に同一**（キー名・エポックミリ秒）。同じGoogleアカウントで
ログインすればAndroid端末とiPhoneの間でそのまま同期される。`PokkeTests` に
「Android版が書いたJSONを読める」ことの回帰テストを入れてある。

### iOSで変えたところ

- **共有拡張はOGPを取らない**: iOSの拡張は別プロセスで短命なため、拡張はURLの保存だけ行い、
  アプリ本体がフォアグラウンド復帰時に `reloadFromDisk()` → `retryMissingMetadata()` で
  タイトル・サムネを埋める（`RootView` の `scenePhase` 監視）
- **アプリ内ブラウザはSFSafariViewController**: AndroidのCustom Tabs相当。
  Safariのログイン状態を引き継ぐので、X・Instagramの投稿もそのまま見られる
- **画像の保存先は写真ライブラリのアルバム「Pokke」**: iOSに `Pictures/Pokke` に当たる
  アプリ専用フォルダが無いため。権限は追加のみ（`NSPhotoLibraryAddUsageDescription`）
- **ネイティブ広告に MediaView を入れている**: iOSのAdMob SDKに入っている広告バリデータが
  「メイン画像/動画にMediaViewを使っていない」を実装エラーとして出すため。
  Androidのレイアウトには無い要素なので、そこだけ縦に1枚多い
- **配色はライト固定**: Android版が `lightColorScheme` 固定なので、`preferredColorScheme(.light)` で揃えた

### アイコンとフォント

Androidと同じ [Lucide](https://lucide.dev) の線画・同じ書体を使っている。
アイコンはライブラリを足さず、Android版と**同じパスデータの文字列**を写して
`SVGPath` で `Path` に起こしている（片方を直したらもう片方も直すこと）。
書体は英数がFigtree・和文がZen Maru Gothicで、`kCTFontCascadeListAttribute` で
1つのスタックに繋いでいる。ライセンス表記は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

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

## App Store 提出

手順と残りの作業は [RELEASE.md](RELEASE.md) にまとめてある。コード側で済んでいるもの:

- [x] アプリアイコン — Androidの `ic_launcher_foreground.xml`（Caprasimoの「P」を
      アウトライン化したもの）から1024pxで書き出し済み。Android版の変更に追従する場合は
      同じベクターを `SVGPath` で描き直す
- [x] `Info.plist` の `SKAdNetworkItems`（Google公式50件）
- [x] プライバシーマニフェスト `PrivacyInfo.xcprivacy`
- [x] 共有拡張の表示名を日英韓で出し分け（`PokkeShare/InfoPlist.xcstrings`）

---

## コマンド

```bash
xcodebuild test -project Pokke.xcodeproj -scheme PokkeTests -destination 'platform=iOS Simulator,name=iPhone 17'
```

```bash
xcodebuild build -project Pokke.xcodeproj -scheme Pokke -destination 'platform=iOS Simulator,name=iPhone 17'
```
# Pokke_iOS
