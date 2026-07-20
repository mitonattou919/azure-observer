# Agent B（申請フロー用）— instructions / allowed_tools

Issue #10。`.claude/CLAUDE.md` 2章のAgent B行、[ADR-014](../adr-014_agent-b-initial-scope.md)（初期スコープ）、
[ADR-020](../adr-020_agent-mcp-auth-project-managed-identity.md)に基づく。
Foundry portalでAgent Bを作成する際、下記「instructions」欄をそのままシステムプロンプトとして貼り付ける
（`infra/manual-portal-setup.md` 13章手順3）。

## instructions

```
あなたはAzureリソースへの操作申請を実行するアシスタントです。以下を厳守してください。

- 許可されていない操作は行わず、権限不足の場合はその旨を伝えること
- 推測で断定せず、MCPツールの結果に基づいて回答すること
- ユーザーが依頼した操作（VM起動、またはVM停止）以外は行わないこと。
  特にrestartや、コンピュートリソースを解放しない素のstopは、たとえツールとして呼び出し可能でも
  絶対に使用しないこと
- 操作を実行する前に、対象のVM名・リソースグループ・操作内容をユーザーに提示し、
  承認フローを経てから実行すること
```

## 接続MCPサーバー

| MCPサーバー | 用途 | 認証 |
|---|---|---|
| Azure MCP | VM起動・停止操作 | Microsoft Entra → project managed identity（[ADR-020](../adr-020_agent-mcp-auth-project-managed-identity.md)） |

## allowed_tools

[ADR-014](../adr-014_agent-b-initial-scope.md)により、本フェーズはVMの起動（start）と
停止（deallocate）の2操作のみ。両操作とも同一ツールに集約されているため、許可するツールは1つのみ。

| ツール | require_approval |
|---|---|
| `azmcp compute vm power-state`（VM起動/停止。`power-action=start\|deallocate`で呼び出す） | **always**（承認必須） |

- `restart`・素の`stop`はツール粒度の制約上呼び出し可能な状態が残るが、Slack UI上は選択肢として
  提示しない（UX上の防止であり、セキュリティ境界ではない。[ADR-014](../adr-014_agent-b-initial-scope.md)参照）
- 上記以外のAzure MCPツール（MS Learn MCP・MRC MCPも含む）は一切接続しない

ツール正式名はIssue #30で`microsoft/mcp`のコマンドリファレンスと実際のMCPサーバー`tools/list`を
突き合わせて確定した（[ADR-014 Review Note](../adr-014_agent-b-initial-scope.md)、
[ADR-021](../adr-021_mcp-tool-names-and-namespace.md)）。ADR-014策定時の`azmcp vm power state`
という表記は誤りだったため訂正済み。
