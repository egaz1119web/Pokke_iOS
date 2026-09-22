# Pokke Analytics 設計（iOS）

Android版と同じFirebaseプロジェクト・イベント名で、保存から再訪までの主要導線を計測する。
URL、タイトル、検索語、タグ名、コレクション名、アカウント情報はイベントに含めない。

## イベント

| イベント | タイミング | パラメータ |
|---|---|---|
| `screen_view` | タブ、詳細、追加、整理画面の表示 | `screen_name`, `screen_class` |
| `onboarding_started` | 初回案内の表示 | なし |
| `onboarding_completed` | 初回案内の完了 | `last_step` |
| `onboarding_skipped` | 初回案内のスキップ | `last_step` |
| `guide_started`, `guide_completed`, `guide_skipped` | 初回後に「使い方」を再表示 | 完了・スキップ時は `last_step` |
| `bookmark_saved` | 手入力・共有拡張からの保存 | `source`, `result`, `has_collection` |
| `bookmark_save_failed` | URL不正・保存上限 | `source`, `reason` |
| `select_content` | 保存済みリンクをブラウザで開く | `content_type=bookmark`, `open_mode` |
| `share` | 保存済みリンクを他アプリへ共有 | `content_type=bookmark`, `item_count` |
| `bookmark_search` | 検索入力が800ms止まったとき | `query_length_bucket`, `result_count`, `tag_filtered` |
| `bookmark_action` | 削除、お気に入り、アーカイブ、リマインダー | `action`, `enabled` |
| `bulk_action` | 一括削除・コレクション振り分け | `action`, `item_count` |
| `collection_action` | コレクションの作成・編集・削除 | `action` |
| `login` | Google／Appleログイン結果 | `method`, `result` |

共有拡張にはFirebase SDKをリンクしない。拡張で発生した保存イベントはApp Groupへ最大100件まで
一時保存し、アプリ本体が次に起動したときFirebaseへ送信する。

## Firebase コンソール設定

1. Firebaseの「プロジェクトの設定 → 統合」でGoogle Analyticsを有効にする。
2. FirebaseのアプリIDとBundle IDがプロジェクト内の `GoogleService-Info.plist` と一致することを確認する。
   `IS_ANALYTICS_ENABLED` は現行SDKの収集ON/OFFキーではない。収集を明示的に無効化する場合は
   アプリの `Info.plist` で `FIREBASE_ANALYTICS_COLLECTION_ENABLED` を使う。本アプリでは未指定のため、デフォルトで収集が有効になる。
3. Analyticsの「カスタム定義」で、`source`, `result`, `reason`, `last_step`, `open_mode`, `action`, `query_length_bucket`, `method` をイベントスコープのカスタムディメンションとして登録する。
4. `bookmark_saved`（`result=created`）、`onboarding_completed`、`select_content` を主要イベントとして扱う。
5. App Store ConnectのApp Privacyで「製品とのやり取り」を分析目的で収集する申告を確認する。

見るべき最初のファネルは `first_open → onboarding_started → bookmark_saved → onboarding_completed`。
継続価値は、保存した利用者の7日・28日後の再訪と `select_content` の発生率で判断する。

## DebugView での確認

Xcodeの Scheme → Run → Arguments に `-FIRAnalyticsDebugEnabled` を追加して起動し、
Firebase Consoleの Analytics → DebugView でイベントとパラメータを確認する。
確認後は起動引数を削除する。
