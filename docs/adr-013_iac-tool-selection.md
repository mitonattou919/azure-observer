# ADR-013: IaCツール選定（Bicep / Terraform）

- Status: Accepted
- Date: 2026-07-19

## Context

Issue #3。Azure基盤プロビジョニング（Managed Identity、RBAC、Container Apps等）を
コード化するにあたり、Bicep / Terraformのどちらを採用するか未確定だった。

検討した選択肢:

- **A. Bicep**
- B. Terraform

検討事項（Issue #3記載）:

- チームの習熟度・既存資産
- Azure専用リソース中心の構成であることを踏まえた保守性

チームの状況として、他チームでのTerraform資産や運用実績はなく、マルチクラウド方針もない。
構成もAzure専用リソース（Managed Identity、Container Apps、Foundry Agent Service等）が
中心であり、AzureネイティブなBicepとの親和性が高い。

## Decision

**選択肢A（Bicep）** を採用する。

- Azure専用構成であるため、Terraformのprovider抽象化によるメリットが薄い一方、
  Bicepはstate管理ファイルが不要でARM/Azure CLIとの統合が直接的
- チームに既存のTerraform資産・運用実績がなく、学習コストの観点でもBicepが有利

## Consequences

- 以降のAzure基盤プロビジョニング（Issue #6, #7, #8）はBicepで実装する
- Managed Identity・RBAC設定のREADME（`CLAUDE.md` 成果物節）はBicepモジュール構成を前提に書く
- 将来マルチクラウド化する場合はTerraformへの移行検討が必要になるが、現時点では対象外

## Review Note (2026-07-20)

Issue #6でのGitHub障害対応として`infra/manual-portal-setup.md`（Bicep未適用時の手動代替手順）を
用意した際、「人間の認知負荷を考えると、初見のリソース種別は障害時の代替としてではなく
最初からポータルで手を動かして理解し、その結果をBicepに落とす順序の方が実は良いのでは」
という気づきが出た。まだ採用に足る検討はしておらず、本ADRの決定（Bicep採用・IaC先出しの
運用）自体は変更しない。将来、手動先行プロセスへの切り替えを検討する場合は本ADRをsupersede
するか追記する形で対応すること。
