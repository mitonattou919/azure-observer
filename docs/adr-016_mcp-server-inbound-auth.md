# ADR-016: Azure MCP Serverのインバウンド保護方式とApp Registration発行主体

- Status: Accepted
- Date: 2026-07-20

## Context

Issue #8。`CLAUDE.md` タスク1は「クライアント側からMCPサーバーを呼ぶ経路は別途Entra ID認証
（App Registration）で保護する」とだけ記載しており、以下が未確定だった。

- Ingressを外部公開(external)にするか、閉域(internal/VNet統合)にするか
- Entra ID認証をどの層で検証するか（Container Apps組み込みのEasy Auth／アプリ層での自前実装）
- 保護対象（MCPサーバー自身）を表すリソース側App Registrationをどのタイミング・どのIssueで作るか
- クライアントはFoundry Agent A/B/Cに加え、App Homeダッシュボード用にAzure MCPを直接呼ぶ
  Backend自身も含まれる（ADR-012）が、Backend用のクライアント側App Registrationの作成主体も
  未確定だった

[[adr-002_per-agent-app-registration]]はAgent A/B/C用のクライアント側App Registrationを
分離する決定のみを扱っており、リソース側App RegistrationやBackend用クライアントの扱いは
対象外だった。

## Decision

- **Ingress**: external（インターネット到達可能なFQDN）とする。Foundry Agent ServiceはVNet統合
  していない外部サービスであり、この段階でPrivate Endpoint/VNet閉域化まで手を出す理由が薄いため。
  代わりにEntra ID認証を保護層とする
- **認証方式**: Azure Container Apps組み込みの **Easy Auth**（`authConfig`）を使う。
  Azure MCP Serverは公式イメージをそのまま自己ホストする前提で、アプリ層への改造を持ち込みたくない。
  Easy Authはプラットフォーム（サイドカー）層でJWT検証を行うため、MCPサーバー本体は無改造のままで済む
- **リソース側App Registration**（MCPサーバー自身を表す、Easy Authのaudienceの元になるApp
  Registration）は **Issue #8で作成する**。Issue #9のタイトルは「Agentごとの」であり、
  Agentに紐付かないサーバー自身の身元をそこに含めるのは筋が違う
- **Backend自身のクライアント側App Registration**も **Issue #8で作成する**。Backendの実装自体は
  Issue #11だが、「MCPサーバーを直接叩く経路の保護」というIssue #8のスコープに含める方が
  責務として自然
- Issue #9は [[adr-002_per-agent-app-registration]] 通り、Agent A/B/C用の3つのクライアント側
  App Registrationの作成のみに専念させる

## Consequences

- Issue #8完了時点で、リソース側App Registration 1つ + Backend用クライアント側App Registration 1つの
  計2つが作成される。Issue #9ではAgent A/B/C用の3つが追加され、最終的にクライアント側は4つになる
- Easy Authの設定はContainer AppのBicepリソース（`authConfig`）に持たせるため、認証ロジックの
  実体はIaCコードとApp Registrationのスコープ定義に閉じる。アプリケーションコード側でのトークン
  検証実装は不要になる
- VNet閉域化を採用しなかったため、Ingressは理論上インターネットから到達可能。Easy Authの設定ミスは
  そのままMCPサーバーへの無認証アクセスに直結するリスクを受容する
  （[[adr-001_mcp-server-topology]]のRBAC二重防御なしと同種の受容済みリスク）
- 将来Private Endpoint化を検討する場合は本ADRをsupersedeする形で別ADRを起こすこと
