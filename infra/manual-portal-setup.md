# Azure Portalでの手動作成手順（Issue #6）

GitHub障害時の代替手段として、Azure Portalから手動でリソースを作成する場合の手順。
通常はBicep（`main.bicep` / `dev.bicepparam`）でのデプロイを優先する。
命名規則・タグの背景は[docs/azure-bicep-guidelines.md](../docs/azure-bicep-guidelines.md)を参照。

## 共通タグ（全リソースに設定）

| キー | 値 |
|---|---|
| `Owner` | `mitonattou919@gmail.com` |
| `Project` | `sre: Azure Observer for SRE` |
| `Environment` | `dev` |

リージョンは全リソース共通で `Japan East`。

---

## 1. Resource Group作成

1. Azure Portal検索バーで「リソース グループ」→ **作成**
2. サブスクリプションを選択
3. **リソースグループ名**: `rg-sre-dev-001`
4. **リージョン**: `Japan East`
5. 「次へ: タグ」→ 上記共通タグを3つとも入力
6. 「確認および作成」→ **作成**

---

## 2. User-Assigned Managed Identity作成

1. 検索バーで「マネージド ID」（Managed Identities）→ **作成**
2. **サブスクリプション**: 同上
3. **リソースグループ**: `rg-sre-dev-001`
4. **リージョン**: `Japan East`
5. **名前**: `id-sre-dev-001`
6. 「タグ」タブで共通タグを入力
7. 「確認および作成」→ **作成**

---

## 3. Storage Account作成（activitylogテーブル用）

1. 検索バーで「ストレージ アカウント」→ **作成**
2. **リソースグループ**: `rg-sre-dev-001`
3. **ストレージアカウント名**: `stsredev001`（英数字のみ、ハイフン不可）
4. **リージョン**: `Japan East`
5. **パフォーマンス**: Standard
6. **冗長性**: LRS（ローカル冗長ストレージ）
7. 「詳細」タブ:
   - **セキュリティで保護された転送が必須**: 有効のまま
   - **最小TLSバージョン**: `バージョン1.2`
8. 「ネットワーク」タブ: デフォルトのままでOK
9. 「データ保護」タブ: デフォルトのままでOK
10. 「タグ」タブで共通タグを入力
11. 「確認および作成」→ **作成**

作成後、追加でBlob公開アクセスを無効化:
- 作成したストレージアカウント → 左メニュー「構成」（Configuration）
- **BLOB匿名アクセスを許可**: **無効** に変更 → 保存

続けてテーブル作成:
- 左メニュー「テーブル」（Data storage内）→ **+ テーブル**
- **テーブル名**: `activitylog`（アンダースコア不可のため。詳細はADR-005 Review Note参照）
- 作成

---

## 4. Key Vault作成

1. 検索バーで「Key Vault」→ **作成**
2. **リソースグループ**: `rg-sre-dev-001`
3. **Key Vault名**: `kv-sre-dev-001`
4. **リージョン**: `Japan East`
5. **価格レベル**: Standard
6. 「アクセス構成」タブ:
   - **アクセス許可モデル**: **Azure ロールベースのアクセス制御 (RBAC)** を選択
     （デフォルトの「Vaultアクセスポリシー」ではない点に注意）
   - 論理的な削除・保持期間: デフォルト（90日）のままでOK
7. 「タグ」タブで共通タグを入力
8. 「確認および作成」→ **作成**

---

## 補足

- Key VaultはRBAC認証のため、Managed Identityへの`Key Vault Secrets User`ロール付与は
  本手順には含まない（別途対応）
- 作成後、リソース名・タグがBicepテンプレートと一致していることを確認しておく。
  GitHub復旧後に同じ値で`az deployment group what-if`を実行すれば「差分なし」になるはず
