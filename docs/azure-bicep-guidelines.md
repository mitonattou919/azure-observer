# Azureリソース・Bicepガイドライン

Azure Observer for SRE のAzureリソース命名・タグ・Bicep構成に関する共通ガイドライン。
IaCツールとしてBicepを採用した経緯は[ADR-013](adr-013_iac-tool-selection.md)を参照。

## 命名規則

パターン: `{type}-{workload}-{env}-{instance}`

| 要素 | 内容 |
|---|---|
| `type` | CAFのリソース略語（`rg`, `id`, `kv` など） |
| `workload` | 3文字固定のサービス識別子。本プロジェクトは `sre` |
| `env` | 3文字固定の環境略語。`prd` / `stg` / `dev` |
| `instance` | ゼロパディング3桁の連番。`001`, `002`... |

例: `rg-sre-dev-001`, `id-sre-dev-001`, `kv-sre-dev-001`

**例外: Storage Account**
Storage Accountはハイフン不可・英数字のみのため、上記パターンをそのまま使えない。
`st` + `workload` + `env` + `instance` を連結した `stsredev001` を基本形とする。

ただしStorage Account名はサブスクリプションではなくAzure全体でグローバル一意のため、
上記パターンでも他テナントに先取りされて衝突することがある（dev環境で実際に発生。
`stsredev001`が使用済みだったため`sa`プレフィックスにフォールバックし`sasredev001`を採用）。
衝突した場合は`st`→`sa`等プレフィックスを変えて回避し、`main.bicep`の
`storageAccountNameOverride`パラメータで実際の値を`{env}.bicepparam`から上書きする。

**注意: Key Vaultも同様にグローバル一意**
Key Vault名（`kv-{workload}-{env}-{instance}`）もAzure全体でグローバル一意のため衝突しうる
（dev環境で実際に発生。`kv-sre-dev-001`が使用済みだったため`instance`を`003`にずらし
`kv-sre-dev-003`を採用）。他リソースの命名規則（`namePrefix`基準）とは独立して、
`main.bicep`の`keyVaultNameOverride`パラメータで個別に上書きする。

## 必須タグ

| タグ | 内容 |
|---|---|
| `Owner` | 所有者のメールアドレス。実装上はプレースホルダー（パラメータ）を入れ、デプロイ時に実値を渡す |
| `Project` | `{workloadコード}: {説明}` 形式。本プロジェクトは `sre: Azure Observer for SRE` |
| `Environment` | `prd` / `stg` / `dev` |

## Bicepディレクトリ構成

```
infra/
  main.bicep          # デプロイのエントリポイント
  types.bicep          # 命名・タグの共有型定義
  {env}.bicepparam     # 環境別パラメータ (dev.bicepparam など)
  modules/
    {resource}.bicep    # リソース種別ごとのまとまりでファイルを分ける
```

- 設定値の型を規定する必要がある場合は `types.bicep` に追加する
- Resource Group自体はBicep化せず、`az group create` で事前に手動作成する運用とする
  （`main.bicep` は `targetScope = 'resourceGroup'` で既存RGへの展開を前提とする）

## 検証手順

1. **静的解析**: `az bicep lint` および `az bicep build --file main.bicep`
2. **バリデーション**: `az deployment group validate --resource-group <rg名> --template-file main.bicep --parameters <env>.bicepparam`
3. **展開前確認**: `az deployment group what-if --resource-group <rg名> --template-file main.bicep --parameters <env>.bicepparam`
4. **E2Eテスト（展開後、余力があれば）**: pytest等でリソースが期待通りデプロイされたか確認

上記は人間の手動実行を基本とする。CI/CD（GitHub Actions等）への組み込みはAzure認証
（OIDC federated credential等）の設計とあわせて別issueで検討する。
