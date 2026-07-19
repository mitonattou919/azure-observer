# ADR-009: MS Learn MCP / MRC MCPのホスティング方式

- Status: Accepted
- Date: 2026-07-19

## Context

`CLAUDE.md` はAzure MCP Serverについてのみ「自己ホスト」と明記しており、MS Learn MCP /
MRC (Microsoft Release Communications) MCPのホスティング方式については記載がなかった。
これが未確定だと、Task 1（デプロイ作業）のスコープが「Azure MCP Serverのみ」なのか
「3つとも自前でホスト」なのかが変わる。

MRC MCPの公開エンドポイントの実在は、社内で別用途にて利用実績があり確認済みである。

## Decision

MS Learn MCP、MRC MCPはいずれも**Microsoftが提供する公開エンドポイントをそのまま利用**し、
自前でのホスティングは行わない。自前ホストが必要なのは、Azureリソースへの実操作を伴い
Managed Identity経由の認証が必要な**Azure MCP Serverのみ**とする。

## Consequences

- Task 1（デプロイ・認証設定）のスコープはAzure MCP Serverに限定される
- MS Learn MCP / MRC MCPへの接続設定（エンドポイントURL、必要であれば認証方式）は
  Foundry Agent A/Cの設定作業に含める
- 公開エンドポイントの仕様変更やレート制限等はMicrosoft側の都合に依存するため、
  障害時のフォールバック（`CLAUDE.md` 7章のエラーハンドリング要件）でカバーする
