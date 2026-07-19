# 要件定義書: Slack × Azure Foundry Agent (Azure MCP Server統合)

- Status: Draft
- Last updated: 2026-07-19
- 実装インストラクション（How）: [`.claude/CLAUDE.md`](../.claude/CLAUDE.md)

## 背景・目的

Slack上でAzure関連の申請・相談・定期レポートを提供する。Foundry Agent Serviceを中核に据え、
リソース操作・コスト確認・ドキュメント参照・アップデート確認を、個別リソースAPIを都度実装するのではなく
**Azure MCP Server** / **MS Learn MCP** / **MRC (Microsoft Release Communications) MCP** の
3つのMCPサーバー経由のツール呼び出しに統合する。

> **未決事項**: このプロジェクトが必要になった経緯（既存の申請フローの何が課題だったか）、
> 関係者・ステークホルダー、期限については本ドラフト作成時点で未整理。[未決事項](#未決事項--オープンクエスチョン)を参照。

## スコープ / スコープ外

### スコープ（本フェーズ）

- Foundry Agent A（相談用）/ Agent B（申請フロー用）/ Agent C（定期バッチ用）の3Agent構成
- Azure MCP Server（自己ホスト、単一構成）、MS Learn MCP、MRC MCP（いずれも公開エンドポイント利用）との統合
- Slack App Home（Agent A用チャット）、既存Block Kit申請フローのAgent B移行、定期レポート通知（Agent C）
- ユーザーごとのスレッド永続化、承認フロー、監査ログ／問い合わせ履歴の統合記録
- Managed IdentityベースのシークレットレスなAzure MCP Server認証、Key Vaultによるその他シークレット管理

### スコープ外（本フェーズでは対応しない）

- Managed IdentityのRBACによる二重防御（[ADR-001](adr-001_mcp-server-topology.md)。将来フェーズで再検討）
- 承認者の明示的な権限管理（バックエンド側の承認者リスト。[ADR-006](adr-006_approval-flow.md)。
  現状はSlackチャンネル参加のみで権限を担保）
- 問い合わせ履歴のセルフ参照UI（[ADR-005](adr-005_storage-and-activity-log.md)。運用者がストレージを直接参照）
- MS Learn MCP / MRC MCPの自前ホスティング（[ADR-009](adr-009_learn-mrc-mcp-hosting.md)。公開エンドポイントを利用）
- 定期レポート通知からApp Homeチャットへの文脈引き継ぎ（`CLAUDE.md` 4章で「余力があれば」とされる項目）

## 全体構成（アーキテクチャ概要）

```
Slack (App Home / Socket Mode / Block Kit申請フロー / 承認チャンネル)
        │  Socket Mode（公開HTTPエンドポイントなし）
        ▼
  Azure Container Apps（Python, minReplicas=1）
        ├─ Slack Bolt イベントハンドラ
        ├─ 週次バッチ用インプロセススケジューラ（APScheduler等）
        └─ Foundry Agent呼び出し・承認フロー制御
        │
        ├──▶ Azure Table Storage（activity_log: chat_turn / tool_call、
        │       スレッドマッピング、承認待ち状態）
        ├──▶ Azure Key Vault（Slack Bot Token, Foundry APIキー等。
        │       ローカル開発時は.envを併用）
        │
        ▼
  Foundry Agent Service（Agent A / B / C、Agentごとに別Entra ID App Registrationで下記に接続）
        ├─ Agent A（相談・読み取り専用）: MS Learn MCP / MRC MCP / Azure MCP
        ├─ Agent B（申請フロー・限定書き込み）: Azure MCP
        └─ Agent C（定期バッチ）: Azure MCP / MRC MCP
                │
                ▼
        Azure MCP Server（自己ホスト・単一インスタンス・単一Managed Identity）
        MS Learn MCP / MRC MCP（Microsoft提供の公開エンドポイント）
```

詳細な決定の背景は [ADR-001](adr-001_mcp-server-topology.md) 〜 [ADR-009](adr-009_learn-mrc-mcp-hosting.md) を参照。

## 機能要件

### Agent A（相談用）

- App Home上のチャットからの質問に対し、読み取り系ツールのみで回答する
- Azureの使い方・仕様に関する質問はMS Learn MCP、最新アップデート・非推奨予定に関する質問はMRC MCP、
  リソースの現状確認はAzure MCPの読み取りツールを使い分ける
- 回答の最後に参照したドキュメント/アップデートのリンクを付ける
- ユーザーは `/reset` 相当のコマンドでスレッドを明示的にリセットできる。加えて30日間操作が
  無かった場合は次回利用時に自動的に新規スレッドへ切り替える（[ADR-008](adr-008_thread-lifecycle.md)）

### Agent B（申請フロー用）

- 既存Block Kit申請フロー（コスト確認・VM起動停止等）を維持しつつ、バックエンドの実装先を
  個別API呼び出しからAzure MCPツール呼び出しに置き換える
- 書き込み系操作は申請→承認→実行の3ステップを維持する
- 承認は固定の1チャンネルに投稿されたボタンで行い、当該チャンネルに参加していることを
  承認権限の証明とみなす（[ADR-006](adr-006_approval-flow.md)）
- 承認待ちのRun状態はTable Storageに保存し、ACAの再起動をまたいでも承認ボタン押下で
  Runを再開できる

### Agent C（定期バッチ用）

- 週次でAzure MCPの読み取りツールから対象サブスクリプションのリソース一覧を取得し、
  MRC MCPから直近1〜2週間分のAzure Updatesを取得して突合する
- 非推奨(Deprecation)・破壊的変更(Breaking Change)は必ずHighに分類し、関係の薄いアップデートは除外する
- 該当ありの場合のみ、リソースごとのセクションブロック（リソース名/種別、影響度バッジ、推奨対応、
  参照リンク）でSlack通知する
- トリガーはACAアプリ内蔵のスケジューラ（追加のAzureリソースなし。[ADR-004](adr-004_in-process-scheduler.md)）

### Backend

- Azure Container Apps（`minReplicas=1`）上のPythonアプリとして、Slack Socket Mode接続、
  Foundry Agent呼び出し、承認フロー制御、バッチスケジューリングを1プロセスに統合する
- Foundry Agent A/B/Cへの接続は、Agentごとに別のEntra ID App Registrationで行う
  （[ADR-002](adr-002_per-agent-app-registration.md)）
- ユーザーID→threadIdマッピング、承認待ち状態、監査ログ／問い合わせ履歴は
  すべてAzure Table Storageの `activity_log` テーブル等に永続化する（[ADR-005](adr-005_storage-and-activity-log.md)）
- Foundry/MCP呼び出し失敗時は、内部エラー詳細を出さずSlackにエラーメッセージのみ返す

### Slack UI

- App Home（Agent A用）: チャット履歴表示、メッセージ入力、送信ボタン。返信は `section` ブロック
  本文＋`context` ブロックで参照リンクを表示
- 承認チャンネル（Agent B用）: 申請内容と承認/却下ボタンを1本の固定チャンネルに投稿
- 定期レポート通知（Agent C用）: ヘッダー「今週のAzure Updates対応チェック」＋対象期間、
  該当ありの場合のみ通知

## 非機能要件（セキュリティ・権限・監査ログ）

- Azure MCP Serverへの認証はManaged Identityによりシークレットレスに構成する
  （[ADR-001](adr-001_mcp-server-topology.md)）
- 権限制御はFoundry側 `allowed_tools` を主な防御層とする。Azure RBACによる独立した
  二重防御は本フェーズでは導入しない（[ADR-001](adr-001_mcp-server-topology.md)、受容リスクとして明記）
- 書き込み系・破壊的操作ツールは `ask every time`（承認必須）に設定する
- 承認権限はSlackの固定チャンネルへの参加をもって認め、バックエンド側の明示的な承認者リストは
  持たない（[ADR-006](adr-006_approval-flow.md)、受容リスクとして明記）
- 全MCPツール呼び出し・会話ターンは `activity_log` に記録し、監査ログと問い合わせ履歴を兼ねる
  （[ADR-005](adr-005_storage-and-activity-log.md)）
- Slack Bot Token・Foundry APIキー等はAzure Key Vault（ACAのManaged Identity参照）に格納する。
  ローカル開発では `.env` を併用する（[ADR-007](adr-007_secrets-management.md)）

## 未決事項 / オープンクエスチョン

- プロジェクトの背景（既存フローの課題）、関係者・ステークホルダー、期限
- IaCツール選定（Bicep / Terraform）
- Agent Bが本フェーズで対応する申請操作の具体的な一覧（VM起動停止以外に何を含めるか）
- アプリケーションのモニタリング/ロギング基盤の要否（Application Insights等をACAの標準ログに
  加えて導入するか）
- スレッド自動リセットの閾値「30日」の妥当性（[ADR-008](adr-008_thread-lifecycle.md)）
- RBACによる二重防御、および承認者の明示的権限管理を将来どのタイミングで再検討するか
  （[ADR-001](adr-001_mcp-server-topology.md) / [ADR-006](adr-006_approval-flow.md)）

## 参照

- 実装インストラクション: [`.claude/CLAUDE.md`](../.claude/CLAUDE.md)
- [ADR-001: Azure MCP Serverの構成トポロジーと防御方式](adr-001_mcp-server-topology.md)
- [ADR-002: Agentごとに個別のEntra ID App RegistrationでMCPサーバーに接続する](adr-002_per-agent-app-registration.md)
- [ADR-003: Backendのホスティング基盤と言語](adr-003_backend-hosting.md)
- [ADR-004: Agent C定期バッチのトリガー方式](adr-004_in-process-scheduler.md)
- [ADR-005: 永続化ストレージとアクティビティログのデータモデル](adr-005_storage-and-activity-log.md)
- [ADR-006: Agent B承認フローの実装方式と承認権限モデル](adr-006_approval-flow.md)
- [ADR-007: シークレット管理方式](adr-007_secrets-management.md)
- [ADR-008: Foundryスレッドのライフサイクル管理](adr-008_thread-lifecycle.md)
- [ADR-009: MS Learn MCP / MRC MCPのホスティング方式](adr-009_learn-mrc-mcp-hosting.md)
