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
