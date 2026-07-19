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
- Slack App Home（ダッシュボード）、DM/「sre」チャンネル@メンションでのAgent A質問対応、
  Agent B申請フロー（App Homeボタン起点で新規設計）、「sre」チャンネルへの定期レポート通知（Agent C）
- ユーザーごとのスレッド永続化、承認フロー、監査ログ／問い合わせ履歴の統合記録
- Managed IdentityベースのシークレットレスなAzure MCP Server認証、Key Vaultによるその他シークレット管理

### スコープ外（本フェーズでは対応しない）

- Managed IdentityのRBACによる二重防御（[ADR-001](adr-001_mcp-server-topology.md)。将来フェーズで再検討）
- 承認者の明示的な権限管理（バックエンド側の承認者リスト。[ADR-006](adr-006_approval-flow.md)。
  現状はSlackチャンネル参加のみで権限を担保）
- 問い合わせ履歴のセルフ参照UI（[ADR-005](adr-005_storage-and-activity-log.md)。運用者がストレージを直接参照）
- MS Learn MCP / MRC MCPの自前ホスティング（[ADR-009](adr-009_learn-mrc-mcp-hosting.md)。公開エンドポイントを利用）
- 定期レポート通知からAgent A（DM/「sre」チャンネル@メンション）への文脈引き継ぎ
  （`CLAUDE.md` 4章で「余力があれば」とされていた項目。App HomeはADR-010によりチャットUIでは
  なくなったため、引き継ぎ先はDM/@メンションに読み替える）

## 全体構成（アーキテクチャ概要）

```
Slack (App Home[ダッシュボード] / DM / 「sre」チャンネル@メンション / Block Kit申請フロー / 承認・通知チャンネル)
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

詳細な決定の背景は [ADR-001](adr-001_mcp-server-topology.md) 〜 [ADR-012](adr-012_app-home-data-source.md) を参照。

## 機能要件

### Agent A（相談用）

- 質問はDM、または「sre」チャンネルでの@メンションから受け付ける（App Home上でのチャット入力は
  提供しない。他チャンネルでの@メンションは正式導線としてサポートしない。
  [ADR-010](adr-010_slack-entry-points-and-channel-routing.md)）
- DMとsreチャンネル@メンションは別々の会話文脈（スレッド）として扱い、共有しない
  （[ADR-011](adr-011_agent-thread-separation.md)）
- 読み取り系ツールのみで回答する
- Azureの使い方・仕様に関する質問はMS Learn MCP、最新アップデート・非推奨予定に関する質問はMRC MCP、
  リソースの現状確認はAzure MCPの読み取りツールを使い分ける
- 回答の最後に参照したドキュメント/アップデートのリンクを付ける
- ユーザーは `/reset` 相当のコマンドで、発行した場所（DM または sreチャンネル）のスレッドのみを
  明示的にリセットできる。加えてentry_pointごとに30日間操作が無かった場合は次回利用時に自動的に
  新規スレッドへ切り替える（[ADR-011](adr-011_agent-thread-separation.md)、
  [ADR-008](adr-008_thread-lifecycle.md)）

### Agent B（申請フロー用）

- 申請の入口はApp Homeのボタン（例: 「VM起動申請」）から開くモーダルとする。既存のBlock Kit申請フロー
  はリポジトリ上に実体が無いため、本フェーズで新規に設計する（対応する具体的な操作一覧はIssue #4で確定）
- バックエンドの実装先は個別API呼び出しではなくAzure MCPツール呼び出しとする
- 書き込み系操作は申請→承認→実行の3ステップを維持する
- 申請ごとに使い捨てのFoundryスレッドを新規作成する。Agent Aの相談スレッドとは共有しない
  （[ADR-011](adr-011_agent-thread-separation.md)）
- 承認は「sre」プライベートチャンネルに投稿されたボタンで行い、当該チャンネルに参加していることを
  承認権限の証明とみなす（[ADR-006](adr-006_approval-flow.md)、[ADR-010](adr-010_slack-entry-points-and-channel-routing.md)）
- 承認待ちのRun状態はTable Storageに保存し、ACAの再起動をまたいでも承認ボタン押下で
  Runを再開できる

### Agent C（定期バッチ用）

- 週次でAzure MCPの読み取りツールから対象サブスクリプションのリソース一覧を取得し、
  MRC MCPから直近1〜2週間分のAzure Updatesを取得して突合する
- 非推奨(Deprecation)・破壊的変更(Breaking Change)は必ずHighに分類し、関係の薄いアップデートは除外する
- 該当ありの場合のみ、リソースごとのセクションブロック（リソース名/種別、影響度バッジ、推奨対応、
  参照リンク）で「sre」プライベートチャンネルに通知する（承認と同一チャンネル。
  [ADR-010](adr-010_slack-entry-points-and-channel-routing.md)）
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

- **App Home（ダッシュボード）**: チャットUIではなく、常設ダッシュボードとする
  （[ADR-010](adr-010_slack-entry-points-and-channel-routing.md)）
  - 当月コスト、アクティブアラート一覧（[ADR-012](adr-012_app-home-data-source.md)のキャッシュから表示）
  - VM起動申請ボタン（押下でAgent B申請モーダルを開く）
  - JIT権限付与のプレースホルダー（将来機能。実装無しでも導線のみ表示）
- **Agent Aとの質問**: DM、または「sre」チャンネルでの@メンションから受け付ける。返信は `section`
  ブロック本文＋`context` ブロックで参照リンクを表示（[ADR-010](adr-010_slack-entry-points-and-channel-routing.md)）
- **「sre」チャンネル（承認・定期通知共用、プライベート）**:
  - 申請内容と承認/却下ボタンを投稿（Agent B用）
  - ヘッダー「今週のAzure Updates対応チェック」＋対象期間、該当ありの場合のみ通知（Agent C用）
  - チャンネル参加＝承認権限のため、招待は運用でSRE室メンバーに限定する

## 非機能要件（セキュリティ・権限・監査ログ）

- Slack App の Bot Token Scopesは `chat:write`（DM・チャンネルへの送信）、`im:history`（DM受信）、
  `app_mentions:read`（「sre」チャンネル@メンション受信）、`commands`（`/reset`相当）、
  `users:read`（表示名解決）を基本とする。App Home（`views.publish`）関連の正確なスコープ名は
  実装時にSlack公式ドキュメントで最終確認する（[ADR-010](adr-010_slack-entry-points-and-channel-routing.md)）
- 承認・定期通知を投稿する「sre」チャンネルはプライベートチャンネルとし、参加を運用で制御することで
  ADR-006の「チャンネル参加＝承認権限」モデルの前提を担保する
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
- アプリケーションのモニタリング/ロギング基盤の要否（Application Insights等をACAの標準ログに
  加えて導入するか）
- スレッド自動リセットの閾値「30日」の妥当性（[ADR-011](adr-011_agent-thread-separation.md)）
- RBACによる二重防御、および承認者の明示的権限管理を将来どのタイミングで再検討するか
  （[ADR-001](adr-001_mcp-server-topology.md) / [ADR-006](adr-006_approval-flow.md)）
- 「sre」チャンネルへの招待・メンバー管理の運用手順（誰がいつ招待・削除するか）
  （[ADR-010](adr-010_slack-entry-points-and-channel-routing.md)）
- App Homeダッシュボードのキャッシュ更新間隔の最終値（アラート15〜30分、コスト1日1回は暫定値。
  [ADR-012](adr-012_app-home-data-source.md)）
- JIT権限付与機能の具体設計（本フェーズはApp Home上のプレースホルダーのみ）

## 参照

- 実装インストラクション: [`.claude/CLAUDE.md`](../.claude/CLAUDE.md)
- [ADR-001: Azure MCP Serverの構成トポロジーと防御方式](adr-001_mcp-server-topology.md)
- [ADR-002: Agentごとに個別のEntra ID App RegistrationでMCPサーバーに接続する](adr-002_per-agent-app-registration.md)
- [ADR-003: Backendのホスティング基盤と言語](adr-003_backend-hosting.md)
- [ADR-004: Agent C定期バッチのトリガー方式](adr-004_in-process-scheduler.md)
- [ADR-005: 永続化ストレージとアクティビティログのデータモデル](adr-005_storage-and-activity-log.md)
- [ADR-006: Agent B承認フローの実装方式と承認権限モデル](adr-006_approval-flow.md)
- [ADR-007: シークレット管理方式](adr-007_secrets-management.md)
- [ADR-008: Foundryスレッドのライフサイクル管理（[ADR-011](adr-011_agent-thread-separation.md)によりsupersede済み）](adr-008_thread-lifecycle.md)
- [ADR-009: MS Learn MCP / MRC MCPのホスティング方式](adr-009_learn-mrc-mcp-hosting.md)
- [ADR-010: Slack UI構成とチャネルルーティング](adr-010_slack-entry-points-and-channel-routing.md)
- [ADR-011: Foundryスレッドモデルの見直し（Agent A入口別・Agent B使い捨て）](adr-011_agent-thread-separation.md)
- [ADR-012: App Homeダッシュボードのデータ取得方式](adr-012_app-home-data-source.md)
- [ADR-013: IaCツール選定（Bicep / Terraform）](adr-013_iac-tool-selection.md)
- [ADR-014: Agent B初期スコープの操作一覧・MCPツール・RBAC・承認境界](adr-014_agent-b-initial-scope.md)
