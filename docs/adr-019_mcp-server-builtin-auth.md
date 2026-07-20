# ADR-019: Azure MCP Serverのインバウンド認証をEasy Authからアプリ内蔵認証に変更

- Status: Accepted
- Date: 2026-07-20
- Supersedes: [[adr-016_mcp-server-inbound-auth]]の「認証方式」の決定のみ（他の決定事項は維持）

## Context

Issue #8実装中、`infra/manual-portal-setup.md`の手順7（コンテナイメージのビルド）で
そもそもこのリポジトリにDockerfileが存在しないことが発覚し、Azure MCP Serverの
実際の配布・実行方式を調査し直した。その過程で[[adr-016_mcp-server-inbound-auth]]の
前提が崩れていることが判明した。

- Azure MCP Server公式イメージ（`mcr.microsoft.com/azure-sdk/azure-mcp`）は、
  HTTPトランスポート（`--transport http`）で起動する場合、`--dangerously-disable-http-incoming-auth`
  フラグを明示的に付けない限り**常に自前でEntra ID受信認証を行う**仕様である
  （[microsoft/mcp: azmcp-commands.md](https://github.com/microsoft/mcp/blob/main/servers/Azure.Mcp.Server/docs/azmcp-commands.md)）
- ADR-016がEasy Authを選んだ理由は「公式イメージを無改造・無認証のまま置き、認証はプラットフォーム層
  （Easy Auth）だけに閉じたい」というものだったが、上記の通りアプリ自身が常時認証を行うため、
  そもそも「アプリ層は無認証」という前提の状態は作れない。Easy Authを追加してもアプリ内蔵認証と
  二重になるだけで、二重防御としての意味も薄い（Managed Identityを分けない[[adr-001_mcp-server-topology]]
  と同様、RBAC側は独立した防御層になっていないのと同種の構造）
- Microsoft公式のリファレンス実装（[Azure-Samples/azmcp-foundry-aca-mi](https://github.com/Azure-Samples/azmcp-foundry-aca-mi)、
  Foundry Agent向けにAzure MCP ServerをACA+Managed Identityでホストする公式サンプル）は、
  Container Apps Easy Authを使わず、コンテナ環境変数（`AzureAd__TenantId`/`AzureAd__ClientId`等）で
  アプリ内蔵認証を直接構成している
- Foundry Agent Service側は「Microsoft Entra認証（agent identity / project managed identity）」という
  接続モードを持ち、FoundryがAgent自身のIDでトークンを取得しBearerヘッダーとして送るだけで済む
  （[Foundry公式ドキュメント](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/mcp-authentication)）。
  このモードはOAuth自動検出（Protected Resource Metadata / `.well-known/oauth-protected-resource`）を
  必要とせず、アプリ内蔵認証と直接組み合わせられる。PRM自動検出が必要になるのはVS Code等
  MCPクライアント固有の話であり、Foundry限定であれば不要
- 手順7・11には他にも認証方式と独立した実装漏れがあった。あわせて記録する:
  - コンテナ起動時に`--transport http`等の起動引数を指定する記載が手順11に無く、
    このままではデフォルトの`stdio`トランスポートで起動してしまいIngress経由で疎通しない
  - リッスンポートは公式イメージが固定で持つ値ではなく、`ASPNETCORE_URLS`環境変数で
    自分たちが指定する値。手順7の「イメージのドキュメントで確認した実値」という記載は誤りで、
    Container Appsの`targetPort`と一致させれば任意の値でよい（本ADRでは公式サンプルに合わせ8080を採用）
  - `--namespace`（有効化するAzure MCPのツール種別）は最大3つまでという制約は無い
    （[Azure-Samples/azmcp-foundry-aca-mi](https://github.com/Azure-Samples/azmcp-foundry-aca-mi)の
    bicepパラメータに`@maxLength(3)`が付いていたのはそのサンプル側の実装都合であり、
    azure-mcp本体の制約ではないことをコマンドリファレンスで確認した）

## Decision

- [[adr-016_mcp-server-inbound-auth]]の「認証方式」をEasy Auth（Container Apps `authConfig`）から
  **アプリ内蔵のEntra ID認証**に変更する。コンテナに`AzureAd__TenantId`/`AzureAd__ClientId`/
  `AzureAd__Instance`環境変数を設定し、値は手順8-1で作成する**リソース側App Registration**
  （`app-sre-dev-001-mcp-server`）のテナントID・クライアントIDを使う
- Ingressの方式（external）、リソース側/Backend用クライアント側App Registrationの発行主体（Issue #8）など、
  ADR-016のその他の決定事項は変更しない
- 手順11のContainer Apps「認証」ブレードでのIDプロバイダー追加は不要になるため削除する
- コンテナのコマンド/引数に`--transport http --outgoing-auth-strategy UseHostingEnvironmentIdentity --mode all --namespace <namespace>`を追加する。
  `--namespace`に何を指定するかはCLAUDE.mdが「Issue #4で確定」としている申請フロー対象操作の
  確定待ちのため、本ADRでは値を確定させない（手順書には仮のプレースホルダーを残す）
- `--read-only`フラグは付けない。[[adr-001_mcp-server-topology]]により単一インスタンス構成で
  Agent Bの書き込み系操作も同じコンテナで扱うため、サーバー全体を読み取り専用にはできない
- ポートは8080を採用し、`ASPNETCORE_URLS=http://+:8080`と`targetPort: 8080`を一致させる

## Consequences

- 手順11でEasy Auth設定が不要になる一方、コンテナ環境変数と起動引数の設定項目が増える
- クライアント側（Backend、Agent A/B/C）が実際にどのスコープ／App Roleでトークンを取得すれば
  アプリ内蔵認証を通過できるかは未検証。[[adr-002_per-agent-app-registration]]の見直し
  （Foundry公式サンプルが採用する「App Role + Project Managed Identityへの直接割り当て」方式との
  整合性検討）とあわせて別Issueで確定させる。本ADRのスコープ外とする
- `--namespace`の対象確定（Issue #4）が終わるまで、手順11のコンテナ引数は完全には確定しない
- Easy Authを使わないため、Container App側のIaC（Bicep）に`authConfig`は不要になり、代わりに
  コンテナの`env`/`args`プロパティが増える。Issue #8のBicep実装時に反映すること

## Review Note (2026-07-20)

本ADRは`infra/manual-portal-setup.md`手順7の「Dockerfileが無くてbuildできない」という実装時の
疑問をきっかけに調査した結果、認証方式（ADR-016）とコンテナ起動引数の両方に見落としがあったことが
判明したもの。[[adr-002_per-agent-app-registration]]（Agentごとのクライアント側App Registration+
シークレット方式）についても、Foundry公式サンプルは全く異なる方式（App Role方式、クライアント側
App Registration自体を作らない）を採っていることが分かったが、影響範囲が大きいため本ADRでは
扱わず、別Issueで改めて検討する。
