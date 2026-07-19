# ADR-015: モニタリング/ロギング基盤の要否

- Status: Accepted
- Date: 2026-07-19

## Context

Issue #5。ACAアプリの標準ログ（stdout、ACA環境に紐づくLog Analyticsワークスペースへ自動収集）
に加えて、Application Insights等の専用APM基盤を導入するかが未確定だった。

[[adr-005_storage-and-activity-log]]で導入済みの `activity_log`（Table Storage）は、
「誰が・いつ・どのAgentが・何のツールを・どんな引数で呼んだか」というビジネス監査ログ・
問い合わせ履歴を扱うものであり、例外・レイテンシ・依存関係呼び出しの成否といった
運用視点のデータは対象外。両者の役割分担、および専用APM基盤の要否を検討した。

検討した選択肢:

- A. Application Insightsを導入する（例外トラッキング・分散トレーシング・アラート）
- **B. 導入しない。ACA標準ログ（stdout、Log Analytics自動連携）＋`activity_log`のみで運用する**

## Decision

**選択肢B** を採用する。本フェーズではApplication Insights等の専用APM基盤を導入しない。
ACAレベルの死活監視・メトリクスアラート（コンテナ再起動、CPU/メモリ逼迫等）も設定しない。

### 役割分担

- **ACA標準ログ（stdout、Log Analytics自動収集）**: 技術的なエラー・例外のログ。
  例外はスタックトレースと関連情報（`thread_id`、Agent種別、ユーザーID等）を付けて
  握りつぶさずログ出力する（Issue #16 エラーハンドリング整備で実装）
- **`activity_log`（Table Storage）**: ビジネス監査ログ・問い合わせ履歴（誰が・いつ・
  どのAgentが・何のツールを呼んだか）。[[adr-005_storage-and-activity-log]]から変更なし

障害の一次検知は、Slack上でエラーメッセージが返る/返らないというユーザー体感に依存する
（`CLAUDE.md` テスト観点6）。

### 再検討トリガー

障害調査においてstdoutログだけでは原因特定に時間がかかる事案が実際に発生したとき、
Application Insights導入を再検討する。他の受容済みリスク（[[adr-001_mcp-server-topology]]の
RBAC二重防御なし、[[adr-006_approval-flow]]の明示的承認者リストなし）と同様、
「規模が大きくなったら」等の曖昧な条件ではなく、実際の運用インシデントを再検討の起点とする方針で
統一する。

## Consequences

- 初期構築・運用コストが下がる（Application Insightsの導入設定・データ取り込み課金が発生しない）
- 分散トレーシング・依存関係の自動失敗検知がないため、Slack→Backend→Foundry Agent→MCPの
  多段呼び出しで障害が起きた場合、原因特定はstdoutログの手動調査に依存する
- アラートが一切ないため、ACAコンテナが完全に落ちた場合でも自動通知されない。気づきの手段は
  ユーザーからの「Slackが反応しない」という申告に依存する
- 将来、再検討トリガーに該当する事案が発生した場合は、本ADRをsupersedeする形で
  Application Insights導入のADRを別途起こすこと
