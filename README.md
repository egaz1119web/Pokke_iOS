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
| `PokkeTests/` | ユニットテスト（Androidの `app/src/test` からの移植＋iOS固有のぶん、136件） | PokkeTests |

- Bundle ID: `com.egaz.stash`（Androidの applicationId と同じ）／拡張は `com.egaz.stash.Share`
- App Group: `group.com.egaz.stash` — 共有拡張とアプリ本体が `stash.json` を共有するのに必要
- 最低iOS: 17.0 / Swift 5 / チーム `W2MGTX4423`

### Androidとの対応

| Android | iOS |
| --- | --- |
| `data/Models.kt` `StashJson.kt` `StashMerge.kt` `TodayPick.kt` `DomainGrouping.kt` `MetadataFetcher.kt` | `PokkeCore/` に同名で1対1移植 |
| `StashRepository`（`filesDir/stash.json`） | `StashRepository` + `StashStore`（App Groupの `stash.json`） |
| `GoogleAuth`（GoogleSignInClient + Firebase Auth） | `AuthService`（GoogleSignIn-iOS + AuthenticationServices + Firebase Auth。**iOSはSign in with Appleも追加**） |
| `FirestoreSync` | `FirestoreSync`（**同じ `users/{uid}` ドキュメント・同じJSON**） |
| `AdsConsent`（UMP） | `AdsConsent`（UMP） |
| `data/AppPrefs.kt`（SharedPreferences） | `AppPrefs`（UserDefaults） |
| `data/CollectionIcons.kt` | `CollectionIcons` |
| `data/ThumbnailReport.kt` | `PokkeCore/ThumbnailReport.swift`（entry番号まで同じフォームを共有） |
| `ui/theme/Theme.kt` `Fonts.kt` | `UI/Theme.swift` `Fonts.swift` |
| `ui/icon/LucideIcons.kt`（ImageVector） | `UI/LucideIcons.swift` ＋ `PokkeCore/SVGPath.swift` |
| `ui/Components.kt` | `UI/Components.swift` |
| `data/ImageSaver.kt`（MediaStore） | `Data/ImageSaver.swift`（Photos） |
| `res/values/strings.xml` + `values-ja` + `values-ko` | `Localizable.xcstrings`（キー名はAndroidと同一） |
| `ShareReceiverActivity` | `PokkeShare`（Share Extension） |

**JSONスキーマはAndroidと同一**（キー名・エポックミリ秒）。同じGoogleアカウントで
ログインすればAndroid端末とiPhoneの間でそのまま同期される。`PokkeTests` に
「Android版が書いたJSONを読める」ことの回帰テストを入れてある。

例外は `items[].remindAt`（リマインダーの通知時刻）と `items[].favorite`（お気に入り）の
2つで、どちらもiOSで足したキー。Android版は知らないので読み飛ばすが、
**Android側でそのアイテムを更新すると値が落ちる**（iOS同士なら同期で運ばれる）。
Android版に同じ機能を入れるときは同じキー名を使うこと。

### iOSで変えたところ

- **共有拡張はOGPを取らない**: iOSの拡張は別プロセスで短命なため、拡張はURLの保存だけ行い、
  アプリ本体がフォアグラウンド復帰時に `reloadFromDisk()` → `retryMissingMetadata()` で
  タイトル・サムネを埋める（`RootView` の `scenePhase` 監視）
- **リンクは常に端末の既定ブラウザで開く**: `SFSafariViewController` も試したが、
  Xのようにアプリ側へ誘導するサービスで正しく表示できなかったため取りやめた
  ([`Common.swift`](Pokke/UI/Common.swift) の `openLink`)
- **画像は写真ライブラリへそのまま追加する**: iOSに `Pictures/Pokke` に当たる
  アプリ専用フォルダが無いため。権限は追加のみ（`NSPhotoLibraryAddUsageDescription`）。
  **アルバムは作らない** — アルバムを作る・探すには読み取りと変更の権限
  （`NSPhotoLibraryUsageDescription`）が要り、追加専用の許可しか宣言していない状態で
  そのAPIに触るとiOSがアプリを強制終了させる
- **シートの中から出すトーストはシート自身に重ねる**: `RootView` に置いた `ToastHost` は
  presentationの下の層にいるので、シートを閉じない操作（画像の保存など）では背後に隠れて
  「押しても何も起きない」ように見える。`.toastOverlay(_:)` を使う
  ([`Components.swift`](Pokke/UI/Components.swift))
- **端末内AIは「試し撃ち」してから入口を出す**: `SystemLanguageModel` が `.available` を
  返してもモデルの実体が無く、生成させると `ModelManagerError 1026` で必ず失敗する
  端末がある。短い生成を1回通してから使えると判断している（`AiAssistant.probeIfNeeded`）
- **ログインはGoogleに加えてSign in with Appleも用意**: App Store審査ガイドライン4.8対応
  （詳細は上の「ログイン / クラウド同期」）
- **オンボーディングは3枚で、2枚目が動く図解**: 「その他→編集→＋→並べ替え→完了」で
  Pokkeを共有シートの先頭に置く操作を、ミニ端末の中で自動再生する
  ([`OnboardingFlow.swift`](Pokke/UI/OnboardingFlow.swift) の `PinPokkeAnimation`)。
  実装は状態パッチの列（タイムライン）を1本のランナーで順に適用する方式で、
  各ステップが絶対値なので頭出し（パッチの畳み込み）とループが壊れない。
  下のボタンはそのまま本物の共有シートを開く（練習ページは挟まない）。
  Android版は静止画の4枚組みのまま
- **設定画面にアカウント削除がある**: 審査ガイドライン5.1.1(v)対応。アカウントを作れる
  アプリは、アプリの中だけで削除まで完了できる必要がある（無効化では足りない）。
  `AuthService.deleteAccount` の順番が肝で、**途中で失敗したらアカウントは消さない**
  — 先にアカウントを消すとFirestoreルール（本人しか触れない）のせいで
  クラウドに残った内容を誰も消せなくなる。Android版にはまだ無い
- **ネイティブ広告に MediaView を入れている**: iOSのAdMob SDKに入っている広告バリデータが
  「メイン画像/動画にMediaViewを使っていない」を実装エラーとして出すため。
  Androidのレイアウトには無い要素なので、そこだけ縦に1枚多い
- **配色はライト固定**: Android版が `lightColorScheme` 固定なので、`preferredColorScheme(.light)` で揃えた
- **古いリンクをまとめて整理できる**: 保存から1週間以上たったものだけを集めたシート
  （[`CleanupSheet.swift`](Pokke/UI/CleanupSheet.swift)）。**既定は全部にチェックが入っていて**、
  残したいものだけ外して消す向きにしてある — 1件ずつ選ばせると、整理したい人ほど手数が増えるため。
  対象にはアーカイブ済みも入れる（保存件数の上限はアーカイブしても減らないので、
  外すと「整理したのに空きが増えない」ことになる）。**お気に入りだけは一覧に出さない**
  — 整理の画面に並べないことが、そのまま「消えない」の保証になる。抽出は
  [`PokkeCore/OldItems.swift`](PokkeCore/OldItems.swift) の純関数。
  入口はホームのバナー（たまってきた時だけ・閉じると1週間出ない）と設定画面の「データ」
- **お気に入り（`favorite`）がある**: ずっと残しておきたいリンクの印で、詳細画面の
  見出し横の星から出し入れする。アーカイブとは別の軸なので、片付けたリンクにも付けられる。
  ホーム上部の絞り込みは「未読／★／アーカイブ」の3つになっていて、★の面だけは
  アーカイブ済みも含めて全部並べる。ピルを星印にしてあるのは、3つとも文字にすると
  隣の表示切替と合わせて小さい端末で横に収まらないため
- **リンクごとにリマインダーを置ける**: 詳細画面から通知時刻を決める
  （[`ReminderSection.swift`](Pokke/UI/ReminderSection.swift)）。候補は「3時間後／明日の朝／週末／
  1週間後」と日時指定で、いずれも**必ず未来になる**値しか作らない
  （[`PokkeCore/ReminderPlan.swift`](PokkeCore/ReminderPlan.swift)）。
  端末内AIが使える端末では時刻の提案も出せる。モデルには日時ではなく
  **「今から何時間後か」**を答えさせている — 日付を直接言わせると、モデルが今日を
  取り違えたときに過去の時刻が返ってきて黙って使えなくなるため。返ってきた値は
  幅（1時間〜90日）に丸め、22時〜翌8時に当たったぶんは朝へ寄せてから見せる。
  OSへの予約（`ReminderScheduler`）は保存内容の**写し**で、個々の操作からではなく
  保存内容ぜんぶを渡した差分で取り直す — そうしないと、クラウド同期で別端末から
  入ってきた変更やまとめて削除したぶんを取りこぼす

### アイコンとフォント

Androidと同じ [Lucide](https://lucide.dev) の線画・同じ書体を使っている。
アイコンはライブラリを足さず、Android版と**同じパスデータの文字列**を写して
`SVGPath` で `Path` に起こしている（片方を直したらもう片方も直すこと）。
書体は英数がFigtree・和文がZen Maru Gothicで、`kCTFontCascadeListAttribute` で
1つのスタックに繋いでいる。ライセンス表記は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

## ログイン / クラウド同期

- `Pokke/GoogleService-Info.plist`（Bundle ID `com.egaz.stash` / プロジェクト `pokke-600ea` — Androidと同一）
- `Pokke/Info.plist` の `CFBundleURLSchemes` に `REVERSED_CLIENT_ID` を登録済み
- 設定画面のログインボタンが有効になり、Googleの認証フローが起動するところまで確認済み
- **Sign in with Apple も用意している（iOS固有）**。App Store審査ガイドライン4.8は
  「サードパーティログイン（Google）を使うなら同等の条件を満たすログインも用意する」ことを
  求めており、それを満たす手段が実質Sign in with Appleしか無いため。Android版には無い
  ([`Pokke/Data/AuthService.swift`](Pokke/Data/AuthService.swift) — 旧 `GoogleAuth.swift`
  をリネームし、Google/Appleどちらのサインインでも同じ `profile`／Firestoreの同期キーに
  行き着くようにしてある)

**plist の置き場所は `Pokke/Pokke/GoogleService-Info.plist`**（アプリのソースフォルダの中）。
プロジェクト直下に置くと同期グループの外なのでバンドルに入らず、`FirebaseApp.configure()` が
走らないまま「設定が未完了です」の表示になる。差し替える時は場所に注意。

Firebase Console 側で残っている確認事項:

- [ ] Authentication → Sign-in method で **Google が有効**か（Android と共用なので済んでいるはず）
- [ ] Authentication → Sign-in method で **Apple を有効化する**（iOS固有・未対応）
- [ ] Firestore ルールが [`firestore.rules`](../../AndroidStudioProjects/Stash/firestore.rules) の内容で公開されているか

Apple Developer Portal 側で残っている確認事項（[RELEASE.md](RELEASE.md) 手順1）:

- [ ] App ID (`com.egaz.stash`) で **Sign In with Apple** Capability を有効化
- [ ] Releaseビルドは有効化前だと
      `doesn't include the Sign In with Apple capability` で失敗する（確認済み）

SHA-1 の登録は Android 固有なので iOS 側では不要。
同期先は Android と同じ `users/{uid}` ドキュメントなので、同じアカウントでログインすれば
Android で保存したリンクがそのまま出てくる（Apple でサインインした場合はAndroid側に
対応アカウントが無いので同期は新規アカウント扱いになる）。

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
