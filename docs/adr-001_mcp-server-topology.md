# ADR-001: Azure MCP Serverの構成トポロジーと防御方式

- Status: Accepted
- Date: 2026-07-19

## Context

`CLAUDE.md` の当初案では、Agentの用途（相談/バッチ用 vs 申請フロー用）ごとに
Managed Identityを分け、Azure RBACによる権限分離を「Foundry側 `allowed_tools` による制御」
とは独立した第二の防御層として位置づけていた（二重防御）。

しかし、Azure MCP Serverの標準実装は「1コンテナ = 1 Managed Identity」が基本であり、
Identityを用途別に分けるには、MCPサーバー自体を用途別に複数デプロイする必要がある。
これは初期構築のインフラ・運用コストを増やす。

検討した選択肢:

- **A. 権限層ごとに複数のAzure MCP Serverインスタンスをデプロイ**し、それぞれに用途別の
  Managed Identityをアタッチする（Reader専用インスタンス／書き込みスコープ付きインスタンス）
- **B. Azure MCP Serverは単一インスタンス・単一Managed Identityとし、権限制御は
  Foundry側の `allowed_tools` にのみ依存する**
- C. 単一インスタンスでリクエストごとにIdentityを動的に切り替える

## Decision

**選択肢B** を採用する。Azure MCP Serverは単一デプロイ・単一Managed Identityとし、
Agent A/B/Cの権限差はFoundry Agent Serviceの `allowed_tools` 設定のみで制御する。
Managed IdentityのAzure RBACによる独立した防御層は、本フェーズでは導入しない。

理由: 公式のAzure MCP Server実装をそのまま使う前提であり、初期段階でインフラ構成を
複雑化させないことを優先した。

## Consequences

- インフラ構成がシンプルになり、初期構築・運用コストが下がる
- 一方で `CLAUDE.md` 6章が想定していた「allowed_tools誤設定時にAzure RBACが最終防波堤になる」
  という二重防御は成立しない。Agent Aやバッチ用の読み取り専用Agentも、技術的には
  書き込み権限を持つIdentityを経由してMCPサーバーに接続することになるため、
  `allowed_tools` の設定ミスがそのままリソース操作事故に直結するリスクを受容する
- 将来的にリスクが許容できなくなった場合は、選択肢Aへの移行（MCPサーバーの権限層別複数化）
  を検討する。これは本ADRをsupersedeする形で別ADRを起こすこと

## Review Note (2026-07-19)

PRレビューにて、単一Identityへの権限付与は「サブスクリプション全体」ではなく
「対象リソースグループ限定」に厳格化すべきという指摘を受けた。これは元々の意図通りであり、
`.claude/CLAUDE.md` タスク1の記述を「Readerロール＋対象操作に必要な最小ロールを
対象リソースグループに限定して同一Identityに付与（サブスク全体への書き込みロール付与は行わない）」
と明記する形で対応した。本ADRの決定内容（選択肢B）自体への変更はなし。
