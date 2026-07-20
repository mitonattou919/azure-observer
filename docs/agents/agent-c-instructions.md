# Agent C（定期バッチ用）— instructions / allowed_tools

Issue #10。`.claude/CLAUDE.md` 2章・5章のAgent C行、[ADR-020](../adr-020_agent-mcp-auth-project-managed-identity.md)に基づく。
Foundry portalでAgent Cを作成する際、下記「instructions」欄をそのままシステムプロンプトとして貼り付ける
（`infra/manual-portal-setup.md` 13章手順3）。実行トリガーはSlackではなくBackendのスケジューラ
（Issue #15で実装、`CLAUDE.md` 5章参照）。

## instructions

```
あなたはAzureリソースとAzure Updatesを突合し、週次レポートを作成するアシスタントです。
以下を厳守してください。

- 許可されていない操作は行わず、権限不足の場合はその旨を伝えること
- 推測で断定せず、MCPツールの結果に基づいて回答すること
- 非推奨(Deprecation)・破壊的変更(Breaking Change)を含むアップデートは必ず影響度Highに分類すること
- 対象リソースと関係の薄いアップデートは除外すること
- 判定の根拠となるアップデート内容を明記し、推測で断定しないこと
```

## 接続MCPサーバー

| MCPサーバー | 用途 | 認証 |
|---|---|---|
| Azure MCP | 対象サブスクリプションのリソース一覧（種別・SKU・リージョン）取得 | Microsoft Entra → project managed identity（[ADR-020](../adr-020_agent-mcp-auth-project-managed-identity.md)） |
| MRC MCP | 直近1〜2週間分のAzure Updates取得 | 提供元の認証方式に従う |

## allowed_tools

読み取り系のみ許可。書き込み系ツールは接続しない。

| ツール | require_approval |
|---|---|
| Azure MCPの読み取り系ツール（リソース一覧・種別・SKU・リージョン取得） | never |
| MRC MCPのアップデート検索・取得ツール一式 | never |

> **要確認**: [Agent A instructions](agent-a-instructions.md)の要確認事項と同様、Azure MCP Serverの
> `--namespace`未確定（`infra/dev.bicepparam`の`mcpServerNamespaces`）とMRC MCPの正式ツール名を、
> 実際のMCPツール一覧に照らして確定させること。
