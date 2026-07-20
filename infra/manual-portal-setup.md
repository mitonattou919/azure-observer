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
   - Storage Account名はAzure全体でグローバル一意のため、`stsredev001`が既に使用済みの場合がある
     （dev環境では実際に衝突し、`sasredev001`を採用した。[docs/azure-bicep-guidelines.md](../docs/azure-bicep-guidelines.md)参照）
   - 別名を使った場合は`infra/dev.bicepparam`の`storageAccountNameOverride`に実際の値を設定すること
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
   - Key Vault名もAzure全体でグローバル一意のため、`kv-sre-dev-001`が既に使用済みの場合がある
     （dev環境では実際に衝突し、`instance`を`003`にずらして`kv-sre-dev-003`を採用した）
   - 別名を使った場合は`infra/dev.bicepparam`の`keyVaultNameOverride`に実際の値を設定すること
4. **リージョン**: `Japan East`
5. **価格レベル**: Standard
6. 「アクセス構成」タブ:
   - **アクセス許可モデル**: **Azure ロールベースのアクセス制御 (RBAC)** を選択
     （デフォルトの「Vaultアクセスポリシー」ではない点に注意）
   - 論理的な削除・保持期間: デフォルト（90日）のままでOK
7. 「タグ」タブで共通タグを入力
8. 「確認および作成」→ **作成**

---

---

## 5. RBACロール付与（Issue #7）

`Key Vault Secrets User`はKey Vault作成時にRBAC認証モデルを選んだ時点でBicep側が
リソーススコープで付与する想定のため、本手順には含まない。ここではリソースグループ
スコープの2ロールのみ手動付与する（[ADR-014](../docs/adr-014_agent-b-initial-scope.md)）。

1. リソースグループ`rg-sre-dev-001`を開く → 左メニュー「アクセス制御(IAM)」
2. **+ 追加** → **ロールの割り当ての追加**
3. **Reader**ロールを選択 → 「次へ」
4. **メンバー**: 「アクセスを割り当てる先」で**マネージド ID**を選択 → **+メンバーを選択**
   → `id-sre-dev-001`を選択 → 「確認および割り当て」
5. 同じ手順をもう一度繰り返し、今度は**Virtual Machine Contributor**ロールで
   `id-sre-dev-001`に割り当てる
   - VMの起動(start)/停止(deallocate)のみが対象操作だが、組み込みロールに限定版が無いため
     採用（ADR-014参照。VM作成・削除・リサイズも技術的に可能な広い権限である点に注意）

---

## 補足

- Key VaultはRBAC認証のため、Managed Identityへの`Key Vault Secrets User`ロール付与は
  1.〜4.の手順には含まない（Key Vault自体の作成時にBicepが付与する想定。手動作成時は
  Key Vaultの「アクセス制御(IAM)」から同様に`Key Vault Secrets User`を`id-sre-dev-001`に
  個別付与すること）
- 作成後、リソース名・タグがBicepテンプレートと一致していることを確認しておく。
  GitHub復旧後に同じ値で`az deployment group what-if`を実行すれば「差分なし」になるはず
