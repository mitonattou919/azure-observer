# ADR-020: Foundry Agent A/B/CのMCP接続認証をproject managed identityに変更

- Status: Accepted
- Date: 2026-07-20
- Supersedes: [[adr-002_per-agent-app-registration]]

## Context

Issue #10（Foundry Agent A/B/Cの作成）着手にあたり、[[adr-019_mcp-server-builtin-auth]]の
Consequencesが残していた懸案（「クライアント側がどのスコープ／App Roleでトークンを取得すれば
アプリ内蔵認証を通過できるか未検証」）を確認した。

Foundry Agent Serviceの公式ドキュメント（[MCP Server Authentication](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/mcp-authentication)）
によると、Agentからカスタム（自己ホスト）MCPサーバーへの認証方式は以下の5種類のみで、
「Agentごとに個別のクライアント側App Registration＋クライアントシークレットを発行する」方式は
このいずれにも該当しない:

- Key-based（APIキー/固定トークン。自動ローテーションなし）
- Microsoft Entra - agent identity（Agent単位のidentity。ただし**Publish後のみ**Agentごとに
  別identityになる。Publish前は全Agent共通のidentityを共有する）
- Microsoft Entra - project managed identity（Foundry Projectのmanaged identityを共有）
- OAuth identity passthrough（ユーザーごとのサインイン。共有識別のバックエンド用途には不向き）
- Unauthenticated access

Microsoft公式のリファレンス実装（[Azure-Samples/azmcp-foundry-aca-mi](https://github.com/Azure-Samples/azmcp-foundry-aca-mi)）も、
リソース側App Registrationにカスタムの**App Role**（`Mcp.Tools.ReadWrite.All`）を1つ定義し、
それをFoundry Projectのmanaged identityに直接割り当てる構成を採っており、Agentごとの個別
App Registrationやクライアントシークレットは使っていない。

[[adr-002_per-agent-app-registration]]は「MCPサーバー側の呼び出しログからどのAgentが呼んだか
判別したい」という監査目的（`CLAUDE.md` 6章）のために個別App Registration方式を選んだが、
上記の通りFoundry Agent Serviceの実際の認証方式とは整合しないため、そのままでは実現できない。

なお、Issue #9では[[adr-002_per-agent-app-registration]]に基づきAgent A/B/C用の3つの
App Registration＋Key Vaultクライアントシークレットをすでに手動作成済みだが、
`infra/manual-portal-setup.md`手順12は当時から「別Issueで見直すまでの暫定」と明記していた
（本ADRがその見直しにあたる）。

## Decision

Foundry Agent A/B/CのMCP接続認証を **Microsoft Entra - project managed identity** 方式に変更する。

- リソース側App Registration（`app-sre-dev-001-mcp-server`、Issue #8で作成済み）にカスタムApp Role
  （`Mcp.Tools.ReadWrite.All`）を1つ定義する
- そのApp RoleをFoundry Projectのmanaged identityに割り当てる
- Agent A/B/CのMCP接続設定は、Foundry portal上で認証方式を「Microsoft Entra → project managed
  identity」として設定する。Agentごとのクライアント側App Registration・クライアントシークレットは
  **作成しない**
- project managed identityは全Agent共有（agent identityモードは採用しない）。理由:
  - agent identityモードはPublish前は結局project内で共有されるため、常時Agentごとの区別を保証しない
  - Publish運用（バージョン管理、Publishのたびに再割り当てが必要か等）のコストが未調査であり、
    今フェーズで導入する説明能力に乏しい
- 「どのAgentが呼んだか」という監査要件は、MCPサーバー側の呼び出しログではなく、
  **Backend側の監査ログ**（`CLAUDE.md` 3章「MCPツール呼び出しを全て監査ログに記録」）で満たす。
  Backendは元々どのAgent（A/B/C）にリクエストを送ったかを把握しているため、Backend側の記録だけで
  「誰が・いつ・どのAgentが・何のツールを・どんな引数で」の要件を充足できる

Issue #9で作成済みの3つのApp Registration（`app-sre-dev-001-mcp-client-agent-a/b/c`）と
Key Vaultシークレット（`mcp-client-secret-agent-a/b/c`）は不要になるため、手動で削除する
（本ADRに伴う後片付けとしてIssue #10側で実施する）。

## Consequences

- `infra/manual-portal-setup.md`手順12は、Agentごとの App Registration作成手順から
  「App Role定義＋project managed identityへの割り当て」手順に置き換える
- Foundry Projectのmanaged identityが漏洩・侵害された場合、Agent A/B/C全てのMCP接続が
  影響を受ける。ただし[[adr-001_mcp-server-topology]]がすでに「Managed Identity単一構成・
  RBACはAgent単位の防御層として機能しない」というリスクを受容しており、本ADRは同種のリスクを
  認証レイヤーにも拡張するのみで、新たなリスク受容パターンではない
- MCPサーバー側の呼び出しログだけでは「どのAgentが呼んだか」を独立に裏付けできなくなる。
  Backend側の監査ログが唯一の情報源になる点に留意する
- Backend自身がApp HomeダッシュボードのためにAzure MCPを直接呼ぶ経路（[[adr-012_app-home-data-source]]）は
  本ADRの対象外。Issue #8で作成したBackend用クライアント側App Registration＋Key Vaultシークレットの
  ままとする（Backendも将来的に自身のManaged Identityでのproject managed identity相当の認証に
  寄せられる余地はあるが、影響範囲が別なので本ADRでは扱わない）
- Issue #9で作成した3つのApp Registration・Key Vaultシークレットの削除が後片付けとして残る
