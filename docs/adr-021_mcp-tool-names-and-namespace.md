# ADR-021: Azure MCP / MRC MCPのツール正式名・namespace確定、コスト/アラート代替指標

- Status: Accepted
- Date: 2026-07-20
- Supersedes: [[adr-012_app-home-data-source]]の「表示するデータの中身（当月コスト／アクティブアラート）」
  の決定のみ（データ取得経路・キャッシュ方式など他の決定事項は維持）

## Context

Issue #30。Issue #10（Agent A/B/Cのinstructions作成）で、`infra/dev.bicepparam`の
`mcpServerNamespaces`（`--namespace`起動引数）とAgent A/B/Cのallowed_toolsが、実際の
Azure MCPツール正式名を確認しないまま「ツール一式」と抽象的な記述のまま残されていた。

`microsoft/mcp`のコマンドリファレンス（[azmcp-commands.md](https://github.com/microsoft/mcp/blob/main/servers/Azure.Mcp.Server/docs/azmcp-commands.md)、
全4791行を取得して全文確認）と、MRC MCPの実エンドポイント（`https://www.microsoft.com/releasecommunications/mcp`）
への実際の`tools/list`呼び出し、および[MS Learn: MRC MCP Server概要](https://learn.microsoft.com/microsoft-365/admin/manage/mrc-mcp)
を突き合わせた結果、以下が判明した。

### 1. VM電源操作ツールの正式名（ADR-014の表記誤り）

正式名は `azmcp compute vm power-state`（namespace: `compute`、
`--power-action start|stop|deallocate|restart`）。[ADR-014](adr-014_agent-b-initial-scope.md)
記載の`azmcp vm power state`は誤記だった（同ADRにReview Noteとして訂正済み）。

### 2. Agent A/C用の読み取り系ツールの正式名

- リソース一覧: `azmcp group list`（RG一覧）、`azmcp group resource list`（RG内リソース一覧、
  namespace: `group`）
- VM詳細: `azmcp compute vm get`（一覧・詳細、namespace: `compute`）

### 3. 重大な想定違い: Azure MCPに「コスト」「アクティブアラート」を返すツールが存在しない

`azmcp-commands.md`全文を確認したが、Cost Management/консumption/billing系のnamespaceは
存在しない。唯一コストに近い`azmcp pricing get`はAzure小売価格表（SKU単価）の照会であり、
実際の当月消費額・請求額は取得できない。

Azure Monitor namespaceにも「発火中のアラート一覧」を返すツールはなく、`activitylog list`
（アクティビティログ）、`log query`、`healthmodels`のみが存在する。

これは`.claude/CLAUDE.md` 4章および[[adr-012_app-home-data-source]]が前提とする
「App HomeでAzure MCPの読み取りツールから当月コスト・アクティブアラートを取得して表示する」
という設計が、現状のAzure MCP Serverでは実現不可能であることを意味する。

### 4. MRC MCPの実体確認

- エンドポイント: `https://www.microsoft.com/releasecommunications/mcp`（Streamable HTTP）
- 認証: 不要（公開エンドポイント、Microsoft API使用条件が適用されるのみ）
- 提供ツール（4つ）: `get_recent_azure_updates` / `get_azure_update_by_id` /
  `get_recent_roadmaps`（M365ロードマップ一覧） / `get_roadmap_by_id`（M365ロードマップ詳細）
  ※実エンドポイントの`tools/list`では`get_recent_m365_roadmaps` / `get_m365_roadmap_by_id`という
  名前で返る場合があり、MS Learn公式ドキュメントの表記（`get_recent_roadmaps` / `get_roadmap_by_id`）
  と一致しない。本プロジェクトでは後者2つ（M365ロードマップ用）はそもそも使わないため実害はないが、
  Foundry portal上でAzure MCPサーバー接続時に実際に列挙される名前を優先して`allowed_tools`に設定すること

## Decision

### `--namespace`確定値

`infra/dev.bicepparam`の`mcpServerNamespaces`を以下に確定する:

```
['compute', 'group', 'advisor', 'resourcehealth']
```

- `compute`: Agent B（VM電源操作）、Agent A/C（VM一覧・詳細）
- `group`: Agent A/C（リソースグループ・リソース一覧）
- `advisor`: Agent A（コスト代替、下記）
- `resourcehealth`: Agent A（アラート代替、下記）

### コスト/アラートの代替指標

[ADR-012](adr-012_app-home-data-source.md)が前提とした「当月コスト」「アクティブアラート」の
実データ取得はAzure MCPでは不可能なため、以下の代替指標に変更する。データ取得経路
（BackendがAgent非経由で直接Azure MCPを呼び、定期キャッシュする方式）自体は
[[adr-012_app-home-data-source]]のまま変更しない。

- **当月コスト → コスト最適化推奨事項一覧**: `azmcp advisor recommendation list --category Cost`
  （状態Newのもののみ返る。実際の$金額ではなく「対応すべきコスト最適化の推奨事項」の一覧）
- **アクティブアラート → サービス正常性イベント一覧**: `azmcp resourcehealth health-events list`
  （ユーザー定義のアラートルールではなく、Azure側のサービス正常性イベント）

Agent A/Cのallowed_toolsにも同様にこの2ツールを read-only で追加する
（[agent-a-instructions.md](agents/agent-a-instructions.md)、
[agent-c-instructions.md](agents/agent-c-instructions.md)反映済み）。

### MRC MCPの`allowed_tools`スコープ

Agent A/Cとも、`get_recent_azure_updates` / `get_azure_update_by_id`のみを許可する。
`get_recent_roadmaps` / `get_roadmap_by_id`（M365ロードマップ）は本プロジェクトのスコープ外
（Azureのみ対象）のため許可しない。認証設定は不要（公開エンドポイント）。

## Consequences

- `.claude/CLAUDE.md` 4章の「当月コスト、アクティブアラート一覧を表示」という記述は、本ADRの
  代替指標（コスト最適化推奨・サービス正常性イベント）に合わせて更新が必要
- App Homeダッシュボードの実際の表示内容が、当初イメージしていた「$いくら使ったか」
  「発火中のアラート」とは異なるものになる。ユーザーへの説明・期待値調整が必要
- 将来Azure MCP ServerがCost Management/Alert系のnamespaceをサポートした場合、
  本ADRをsupersedeする形で実データ取得に置き換えを検討する
- Issue #13〜#15（Agent A/B/C実装）はこのADRで確定したツール名・namespaceを前提に進められる
