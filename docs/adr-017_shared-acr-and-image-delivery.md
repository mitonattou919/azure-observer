# ADR-017: 共有ACRの利用とコンテナイメージ配布方式

- Status: Accepted（「イメージ配布方式」の決定のみ一部Superseded by [[adr-019_mcp-server-builtin-auth]]）
- Date: 2026-07-20

## Context

Issue #8。Azure MCP ServerをContainer Appsにデプロイするには、コンテナイメージを置くレジストリと、
イメージのビルド・配布フローが要る。組織側に共通のAzure Container Registry
（`crmngdev001`、リソースグループ`rg-mng-dev-001`、`rg-sre-dev-001`とは別RG・同一サブスク）が
既にあり、プロジェクト固有のACRは作らずこれを使う組織ルールがあることが判明した。

これに伴い、以下が未確定だった。

- `rg-sre-dev-001`スコープの`main.bicep`から、別RGにある既存ACRへのAcrPullロール割り当てを
  どうBicepで表現するか
- Managed Identity（`id-sre-dev-001`）へのAcrPull付与状況（未付与、Issue #8で新規に行う）
- イメージのビルド〜共有ACRへのpushフローをどうするか（CI/CD化するか、手動運用にするか）

`docs/azure-bicep-guidelines.md`には「CI/CD（GitHub Actions等）への組み込みはAzure認証
（OIDC federated credential等）の設計とあわせて別issueで検討する」と既に明記されている。

## Decision

- **クロスRGロール割り当て**: 新規モジュール`infra/modules/acr-rbac.bicep`を作る。中身はACRを
  `existing`参照し、そのスコープで`AcrPull`ロールを`id-sre-dev-001`に割り当てるだけ。
  `main.bicep`からは`scope: resourceGroup(acrResourceGroupName)`を指定してこのモジュールを呼び、
  `rg-mng-dev-001`側にデプロイする（同一サブスクリプション内なのでtargetScope自体は変更不要）
- ACR名・ACRのリソースグループ名は`main.bicep`の**必須パラメータ**として受け取り、実値
  （`acrName=crmngdev001`, `acrResourceGroupName=rg-mng-dev-001`）は`dev.bicepparam`に書く。
  Storage AccountやKey Vaultの`NameOverride`パラメータ（グローバル一意衝突時の上書き用、
  デフォルト空文字）とは性質が異なり、これは外部共有リソースへの素直な参照なので既定値は持たせない
- **イメージ配布**: CI/CDは組まず、`docker build` + `az acr login --name crmngdev001` +
  `docker push`による**手動運用**とする。手順は`infra/manual-portal-setup.md`と同様の位置づけで
  `infra/`配下に手動デプロイ手順としてまとめる。`main.bicep`側はイメージのフルリファレンス
  （`crmngdev001.azurecr.io/<repo>:<tag>`）をパラメータとして受け取るのみとし、ビルド自体は
  Bicepの外に置く
- CI/CD化は`azure-bicep-guidelines.md`の既存方針通り別issueとして切り出す（本ADRのスコープ外）

## Consequences

- 共有ACR側の管理主体（誰がリポジトリ構成やイメージのライフサイクルを決めるか）は本プロジェクトの
  外にあるため、ACR側の変更（削除・アクセス制御変更等）が本プロジェクトに影響しうる依存関係が生まれる
- 手動pushのため、デプロイ担当者がローカルで`az acr login`できるAzure権限（ACRへのpush権限）を
  個別に持っている必要がある
- 将来CI/CD化する際は、`main.bicep`のイメージ参照パラメータ化はそのまま活かせる
  （ビルド成果物の受け渡し口を変えるだけで済む）

## Superseded (2026-07-20)

「イメージ配布」の`docker build` + `docker push`という手段のみ[[adr-019_mcp-server-builtin-auth]]で
supersedeした。Azure MCP Serverは公式イメージ（`mcr.microsoft.com/azure-sdk/azure-mcp`）を
無改造で自己ホストする前提のためこのリポジトリにDockerfileは存在せず、`docker build`できないことが
Issue #8実装中に判明したため。実際の配布手段は`az acr import`（公式イメージを共有ACRへ直接コピー）に
変更する。CI/CDを組まず手動運用とする方針、クロスRGロール割り当て（`acr-rbac.bicep`）、
`main.bicep`がイメージのフルリファレンスをパラメータとして受け取る設計など、本ADRの他の決定事項は
変更していない。
