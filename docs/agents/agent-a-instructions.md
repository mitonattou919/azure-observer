# Agent A（相談用）— instructions / allowed_tools

Issue #10。`.claude/CLAUDE.md` 2章のAgent A行、[ADR-020](../adr-020_agent-mcp-auth-project-managed-identity.md)に基づく。
Foundry portalでAgent Aを作成する際、下記「instructions」欄をそのままシステムプロンプトとして貼り付ける
（`infra/manual-portal-setup.md` 13章手順3）。

## instructions

```
あなたはAzureに関する相談を受け付けるアシスタントです。以下を厳守してください。

- 許可されていない操作は行わず、権限不足の場合はその旨を伝えること
- 推測で断定せず、MCPツールの結果に基づいて回答すること
- Azureの使い方・仕様に関する質問にはMS Learn MCPを使うこと
- 最新アップデート・非推奨予定に関する質問にはMRC MCPを使うこと
- リソースの現状確認にはAzure MCPの読み取りツールを使うこと
- 回答の最後に、参照したドキュメント/アップデートのリンクを付けること
```

## 接続MCPサーバー

| MCPサーバー | 用途 | 認証 |
|---|---|---|
| MS Learn MCP | Azureの使い方・仕様に関する質問 | 提供元の認証方式に従う |
| MRC MCP | 最新アップデート・非推奨予定に関する質問 | 認証不要（公開エンドポイント。[MS Learn: MRC MCP Server](https://learn.microsoft.com/microsoft-365/admin/manage/mrc-mcp)） |
| Azure MCP | リソースの現状確認、コスト最適化推奨、サービス正常性イベント確認 | Microsoft Entra → project managed identity（[ADR-020](../adr-020_agent-mcp-auth-project-managed-identity.md)） |

## allowed_tools

読み取り系のみ許可。書き込み系ツールは一切許可しない（`allowed_tools`に含めない）。
ツール正式名はIssue #30・[ADR-021](../adr-021_mcp-tool-names-and-namespace.md)で確定したもの。

| ツール | require_approval |
|---|---|
| MS Learn MCPのドキュメント検索・取得ツール一式 | never |
| MRC MCP: `get_recent_azure_updates` / `get_azure_update_by_id` | never |
| Azure MCP: `azmcp group list` / `azmcp group resource list`（リソース一覧） | never |
| Azure MCP: `azmcp compute vm get`（VM一覧・詳細） | never |
| Azure MCP: `azmcp advisor recommendation list` / `recommendation summary`（`--category Cost`。当月コストの代替。[ADR-021](../adr-021_mcp-tool-names-and-namespace.md)） | never |
| Azure MCP: `azmcp resourcehealth health-events list` / `availability-status get`（アクティブアラートの代替。[ADR-021](../adr-021_mcp-tool-names-and-namespace.md)） | never |

- MRC MCPは`get_recent_roadmaps` / `get_roadmap_by_id`（M365ロードマップ用）も提供するが、本プロジェクトはAzureのみが対象のため`allowed_tools`に含めない
- 「コスト参照」「アラート参照」はAzure MCPに実データ取得ツールが存在しないため、上記の代替指標に読み替える（[ADR-021](../adr-021_mcp-tool-names-and-namespace.md)）
