# TIPSY 本番導入手順

## 1. Supabaseプロジェクト

1. 店舗専用のSupabaseプロジェクトを東京リージョンで作成する。
2. Authでオーナーのメールアドレスと強いパスワードを登録する。
3. SQL Editorで `supabase/migrations/202608050001_initial_schema.sql` を実行する。
4. `supabase/seed.sql` の `OWNER_USER_ID` をAuthユーザーIDに置き換えて一度だけ実行する。
5. Storageに非公開の `payment-qr` バケットが作成されたことを確認する。

## 2. 環境変数

`.env.example` を `.env.local` にコピーし、SupabaseのProject Settings > APIから値を設定する。

- `NEXT_PUBLIC_SUPABASE_URL`: Project URL
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`: Publishable key
- `SUPABASE_SERVICE_ROLE_KEY`: サーバー専用。ブラウザに公開しない
- `SESSION_SECRET`: 32文字以上のランダム文字列

## 3. 必須セキュリティ設定

- 本番とテストでSupabaseプロジェクトを分ける。
- Supabase Authの漏洩パスワード保護とMFAをオーナーに設定する。
- 初期PIN `1234` / `5678` は初回ログイン直後に変更する。
- Vercelには `.env.local` をアップロードせず、Environment Variablesへ個別登録する。
- Service Role Keyを `NEXT_PUBLIC_` で始まる変数に絶対に入れない。
- SupabaseのDatabase Backupsを確認し、本番ではProプラン以上を使用する。

## 4. 店舗導入前試験

- 現金、QR、売掛、その他を各10件以上テストする。
- 午前6時前後の営業日集計を確認する。
- 2台以上で同じ卓を同時操作し、二重会計が起きないことを確認する。
- 会計取消、売掛入金、商品価格変更後の過去伝票を確認する。
- 実機レシートプリンターで日本語、合計、税額、改ページを確認する。
- ネット切断時の表示と復旧後の状態を確認する。
- バックアップからテスト環境へ復元できることを確認する。

## 5. 本番移行判定

上記試験をすべて完了し、テスト営業を最低3営業日行ってから本番会計へ切り替える。
