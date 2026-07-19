# ADR-005: 永続化ストレージとアクティビティログのデータモデル

- Status: Accepted
- Date: 2026-07-19

## Context

以下2つの永続化要件があった。

1. ユーザーID→Foundry `threadId` のマッピング、およびAgent B申請の承認待ち状態
   （`CLAUDE.md` 3章・[[adr-006_approval-flow]]）
2. 監査ログ（`CLAUDE.md` 6章: 誰が・いつ・どのAgentが・何のツールを・どんな引数で呼んだか）と、
   ユーザーからの要望である「問い合わせ履歴」（Agent A/B/Cとのやり取りの記録）

2つの要件は粒度が異なる（監査ログ=ツール呼び出し単位、問い合わせ履歴=会話ターン単位）が、
「誰が・いつ・何をしたか」という点で重なりが大きく、別々のストアで二重管理すると
運用負荷が増える。

ストレージ選定の選択肢:

- **A. Azure Table Storage**
- B. Azure Cache for Redis
- C. Azure Database for PostgreSQL Flexible Server

## Decision

ストレージは **Azure Table Storage** を採用する。

データモデルは単一テーブル `activity_log` に統合し、`record_type` で種別を分ける。

```
PartitionKey: user_id (or date)
RowKey: timestamp + record_id
record_type: "chat_turn" | "tool_call"
---
chat_turn:  agent, question, answer, referenced_links, thread_id
tool_call:  agent, tool_name, arguments, result_summary, approved_by(nullable), related_chat_turn_id
```

`tool_call` レコードは `related_chat_turn_id` で対応する `chat_turn` に紐付ける。
これにより、監査ログ要件と問い合わせ履歴要件を同一データソースから満たす。

スレッドマッピング（user_id → threadId）および承認待ち状態も、同じTable Storageアカウント内
（別テーブルまたは別`record_type`）で管理する。

## Consequences

- サーバーレスKVSのため管理コストがほぼゼロ。ACA + Pythonとの相性も良い（`azure-data-tables` SDK）
- 監査ログと問い合わせ履歴を二重管理しなくて済む
- 複雑な集計・検索クエリ（例: 週次レポートの横断検索）が将来必要になった場合、Table Storageの
  クエリ機能は限定的なため、PostgreSQL等への移行を再検討する必要がある
- 問い合わせ履歴の閲覧UIは本フェーズのスコープ外。運用者がTable Storageを直接参照する運用とする
