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
| VM電源操作ツール（起動/停止。ADR-014内の表記は`azmcp vm power state`、`power-action=start\|deallocate`で呼び出す） | **always**（承認必須） |

- `restart`・素の`stop`はツール粒度の制約上呼び出し可能な状態が残るが、Slack UI上は選択肢として
  提示しない（UX上の防止であり、セキュリティ境界ではない。[ADR-014](../adr-014_agent-b-initial-scope.md)参照）
- 上記以外のAzure MCPツール（MS Learn MCP・MRC MCPも含む）は一切接続しない

> **要確認**: ツール正式名は`azmcp compute vm power-state`である可能性がある（`microsoft/mcp`の
> コマンドリファレンス上の表記と、ADR-014策定時に記録された`azmcp vm power state`という表記に
> 差異がある）。Foundry portal上でAzure MCPサーバーに接続した際に実際に列挙されるツール名で
> 確定させ、必要であれば別途ADR-014の表記を追補すること。
