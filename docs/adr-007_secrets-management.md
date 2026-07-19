# ADR-007: シークレット管理方式

- Status: Accepted
- Date: 2026-07-19

## Context

`CLAUDE.md` 6章は「Slack Bot Token, Foundry APIキー等はSecrets管理(環境変数 or Key Vault)に格納」
とだけ規定し、方式は未確定だった。一方 [[adr-001_mcp-server-topology]] により、
Azure MCP Serverへの認証はManaged Identity経由でシークレットレスに構成することが既に決まっている。

## Decision

- 本番環境（ACA）では **Azure Key Vault + ACAのManaged Identity参照機能** を使う。
  ACAに既存のManaged Identity（[[adr-001_mcp-server-topology]]）に `Key Vault Secrets User`
  ロールを追加付与し、新たなIdentityは作らない
- ローカル開発環境では **`.env` ファイルを併用**する

## Consequences

- Managed Identityへの認証方式の一本化という思想を、Azure MCP Server認証以外のシークレットにも
  適用できる
- 追加で必要なAzureリソースはKey Vault 1つとロール割り当てのみで、大きな複雑化にはならない
- ローカル開発者は`.env`にシークレットを平文で置くことになるため、`.gitignore`での除外や
  `.env.example`の整備など、リポジトリ運用上の注意が必要
