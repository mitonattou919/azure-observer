# ADR-002: Agentごとに個別のEntra ID App RegistrationでMCPサーバーに接続する

- Status: Accepted
- Date: 2026-07-19

## Context

[[adr-001_mcp-server-topology]] により、Azure MCP Serverは単一インスタンス・単一Identityとなり、
Azure RBACによる呼び出し元Agentの区別ができなくなった。

一方で `CLAUDE.md` 6章は監査ログ要件として「誰が・いつ・どのAgentが・何のツールを・
どんな引数で呼んだか」を明記しており、「どのAgentが呼んだか」をMCPサーバー側のログからも
判別できる必要がある。

クライアント側の認証（Entra ID App Registration、MCPサーバー自体のAzureに対する認証とは別レイヤー）
をAgent A/B/Cで共有するか分けるかが論点になった。

## Decision

Agent A / Agent B / Agent Cは、それぞれ**別々のEntra ID App Registration**を使って
MCPサーバーに接続する。MCPサーバー自体のManaged Identity（[[adr-001_mcp-server-topology]]参照）は
共通のまま変更しない。

## Consequences

- MCPサーバー側の呼び出しログに残るクライアントトークンのaud/appidから、
  どのAgent経由の呼び出しかを技術的に判別できる
- App Registrationの作成・管理対象が3つに増えるが、Azure RBAC設計のような複雑さは伴わず
  コストインパクトも小さい
- 将来Agentが増えた場合も同じパターン（Agent追加 = App Registration追加）で拡張できる
