# infra

Azure Observer for SRE のAzure基盤をBicepでプロビジョニングする（[ADR-013](../docs/adr-013_iac-tool-selection.md)）。

## 構成

```
infra/
  main.bicep          # resourceGroupスコープ。既存RGにリソースを展開する
  types.bicep          # 命名・タグの共有型定義
  {env}.bicepparam     # 環境別パラメータ (dev.bicepparam など)
  modules/
    managed-identity.bicep
    storage.bicep       # activity_log用Table Storage (ADR-005)
    key-vault.bicep      # シークレット管理用Key Vault (ADR-007)
    rbac.bicep           # RG限定のReader/Virtual Machine Contributor付与 (Issue #7, ADR-014)
```

Resource Group自体はBicep化せず、`az group create` で事前に手動作成する（`main.bicep` は
`targetScope = 'resourceGroup'` で既存RGへの展開を前提とする）。

命名規則・必須タグ・検証手順の詳細は
[docs/azure-bicep-guidelines.md](../docs/azure-bicep-guidelines.md) を参照。

## Resource Group作成（手動）

```bash
az group create \
  --name rg-sre-dev-001 \
  --location japaneast \
  --tags Owner=REPLACE_ME@example.com "Project=sre: Azure Observer for SRE" Environment=dev
```

## デプロイ

```bash
az deployment group create \
  --resource-group rg-sre-dev-001 \
  --template-file main.bicep \
  --parameters dev.bicepparam
```

## 検証手順

`az bicep lint/build` → `validate` → `what-if` の順で確認する。詳細は
[docs/azure-bicep-guidelines.md](../docs/azure-bicep-guidelines.md) を参照。

## 補足: activity_logテーブル名について

[ADR-005](../docs/adr-005_storage-and-activity-log.md) ではテーブル名を `activity_log` としているが、
Azure Table Storageのテーブル名はアンダースコアを含められない（英数字のみ、3〜63文字）制約があるため、
実装上は `activitylog` とする（ADR-005 Review Note参照）。
