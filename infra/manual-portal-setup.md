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

## 6. 共有ACRへのAcrPullロール割り当て（Issue #8, ADR-017）

組織共通のACR（`crmngdev001`、リソースグループ`rg-mng-dev-001`）を使う。プロジェクト固有のACRは作らない。

1. ACR `crmngdev001`（`rg-mng-dev-001`）を開く → 左メニュー「アクセス制御(IAM)」
2. **+ 追加** → **ロールの割り当ての追加**
3. **AcrPull**ロールを選択 → 「次へ」
4. **メンバー**: **マネージド ID**を選択 → **+メンバーを選択** → `id-sre-dev-001`
   （`rg-sre-dev-001`側のIdentity）を選択 → 「確認および割り当て」

---

## 7. コンテナイメージの共有ACRへの取り込み（Issue #8, ADR-017, ADR-019）

Azure MCP Serverは公式イメージ（`mcr.microsoft.com/azure-sdk/azure-mcp`）をそのまま自己ホストする
前提のため、このリポジトリにDockerfileは無く、`docker build`は行わない
（[ADR-019](../docs/adr-019_mcp-server-builtin-auth.md)）。公式イメージを共有ACRへコピーするだけでよい。
CI/CDは組まず手動運用とする。

```bash
az acr import \
  --name crmngdev001 \
  --source mcr.microsoft.com/azure-sdk/azure-mcp:latest \
  --image azure-mcp-server:<タグ>
```

（`az acr login`やローカルへのpullは不要。ACR間で直接イメージがコピーされる）

- `<タグ>`は`infra/dev.bicepparam`の`mcpServerImage`に反映すること
- リッスンポートは公式イメージが固定で持つ値ではなく、`ASPNETCORE_URLS`環境変数（手順11参照）で
  自分たちが指定する値。Container Appsの`targetPort`と一致させれば任意でよいが、本手順では
  Microsoft公式サンプル（[azmcp-foundry-aca-mi](https://github.com/Azure-Samples/azmcp-foundry-aca-mi)）
  に合わせて**8080固定**を採用する。`mcpServerContainerPort`には`8080`を設定すること

---

## 8. Entra ID App Registration作成（Issue #8, ADR-016, ADR-019）

MCPサーバーを表す**リソース側**と、Backend用の**クライアント側**の2つを作成する
（Agent A/B/C用のクライアント側App RegistrationはIssue #9で別途作成する）。

リソース側App Registrationのクライアント ID/テナントIDは、`dev.bicepparam`だけでなく
手順11のコンテナ環境変数（`AzureAd__ClientId`/`AzureAd__TenantId`）でも使う
（MCPサーバー自身がこの値でEntra ID受信認証を行うため。ADR-019）。
なお、以下の`user_impersonation`委任スコープ+クライアントシークレットという方式が
最終形として適切かは未検証（Foundry公式サンプルはApp Role方式を採る）。別Issueで見直し予定。

### 8-1. リソース側App Registration（MCPサーバー自身）

1. 検索バーで「Microsoft Entra ID」→ 左メニュー「アプリの登録」→ **新規登録**
2. **名前**: `app-sre-dev-001-mcp-server`
3. サポートされているアカウントの種類: 「この組織ディレクトリのみ」
4. リダイレクトURIは空のまま → **登録**
5. 登録後、左メニュー「APIの公開」→ **アプリケーションID URIを設定**（既定値 `api://<クライアントID>`のままでよい）
6. 同じ画面で **+ スコープの追加** → スコープ名 `user_impersonation`、同意できるユーザー:
   管理者のみ、説明を適当に入力 → **スコープの追加**
7. 「概要」画面の**アプリケーション(クライアント)ID**を控える →
   `infra/dev.bicepparam`の`mcpServerResourceAppRegistrationClientId`に設定する

### 8-2. クライアント側App Registration（Backend用）

1. 「アプリの登録」→ **新規登録**
2. **名前**: `app-sre-dev-001-mcp-client-backend`
3. サポートされているアカウントの種類: 「この組織ディレクトリのみ」→ **登録**
4. 左メニュー「APIのアクセス許可」→ **+ アクセス許可の追加** → 「自分のAPI」タブ →
   `app-sre-dev-001-mcp-server`を選択 → `user_impersonation`スコープにチェック → **アクセス許可の追加**
5. 同じ画面で **管理者の同意を与えます** をクリック
6. Backendが自身の資格情報（Managed Identity）でトークンを取得できるよう、左メニュー
   「証明書とシークレット」で必要に応じてクライアントシークレットを発行する
   （Managed Identity経由のフェデレーション資格情報を使う場合はシークレット発行不要。
   実装方式はIssue #11で確定させる）
7. 「概要」画面の**アプリケーション(クライアント)ID**を控える →
   `infra/dev.bicepparam`の`mcpServerAllowedClientAppIds`に追記する

---

## 9. Log Analyticsワークスペース作成（Issue #8, ADR-015, ADR-018）

1. 検索バーで「Log Analytics ワークスペース」→ **作成**
2. **リソースグループ**: `rg-sre-dev-001`
3. **名前**: `log-sre-dev-001`
4. **リージョン**: `Japan East`
5. 「タグ」タブで共通タグを入力 → **確認および作成**

---

## 10. Container Apps Environment作成（Issue #8, ADR-018）

組織共通のEnvironmentは存在しないため新規作成する（将来Backend用Container App(Issue #11)もここに載せる）。

1. 検索バーで「Container Apps 環境」→ **作成**
2. **リソースグループ**: `rg-sre-dev-001`
3. **名前**: `cae-sre-dev-001`
4. **リージョン**: `Japan East`
5. 「監視」タブ: **Log Analyticsワークスペース**に手順9で作成した`log-sre-dev-001`を選択
6. 「タグ」タブで共通タグを入力 → **確認および作成**

---

## 11. Azure MCP Server Container App作成（Issue #8, ADR-017, ADR-018, ADR-019）

1. 検索バーで「コンテナー アプリ」→ **作成**
2. **リソースグループ**: `rg-sre-dev-001`
3. **コンテナー アプリ名**: `ca-sre-dev-001-mcp`
4. **リージョン**: `Japan East`
5. **Container Apps 環境**: 手順10で作成した`cae-sre-dev-001`を選択
6. 「コンテナー」タブ:
   - **イメージのソース**: Azure Container Registry
   - **レジストリ**: `crmngdev001`（`rg-mng-dev-001`。ドロップダウンに出ない場合はログインサーバー
     `crmngdev001.azurecr.io`を直接入力）
   - **イメージ**・**タグ**: 手順7でimportした値
   - **コマンドの上書き/引数**（詳細設定。UIの表示場所が変わっている場合は作成後に
     コンテナー編集画面から設定してもよい）:
     `--transport http --outgoing-auth-strategy UseHostingEnvironmentIdentity --mode all --namespace <namespace>`
     - `<namespace>`（有効化するAzure MCPのツール種別。例: `monitor`, `compute`等）はIssue #4で
       申請フロー対象操作が確定してから埋める。3つまでという制限は無い（ADR-019）
     - `--read-only`は付けない。Agent Bの書き込み系操作も同じコンテナで扱うため（ADR-001, ADR-019）
   - **環境変数**:
     - `AZURE_MCP_INCLUDE_PRODUCTION_CREDENTIALS=true`
     - `AZURE_CLIENT_ID=<id-sre-dev-001のクライアントID>`
     - `AZURE_TOKEN_CREDENTIALS=managedidentitycredential`
     - `ASPNETCORE_ENVIRONMENT=Production`
     - `ASPNETCORE_URLS=http://+:8080`
     - `AzureAd__Instance=https://login.microsoftonline.com/`
     - `AzureAd__TenantId=<テナントID>`
     - `AzureAd__ClientId=<手順8-1 app-sre-dev-001-mcp-serverのクライアントID>`
     - `AZURE_MCP_DANGEROUSLY_DISABLE_HTTPS_REDIRECTION=true`（Container Apps Ingressで
       HTTPSは終端済みのため。コンテナ内部はHTTPで待ち受ける想定。詳細はADR-019参照）
7. 「取り込み(Ingress)」タブ:
   - **Ingress**: 有効
   - **トラフィックの取り込み元**: どこからでも受け入れる（external）
   - **ターゲットポート**: `8080`（手順7参照）
8. 作成後、左メニュー「ID」→ **ユーザー割り当て済み** → `id-sre-dev-001`を追加
9. 左メニュー「レジストリ」で、認証方式を**マネージドID**に変更し、手順8で追加したIDを選択
   （管理者資格情報は使わない）
10. 左メニュー「スケール」→ **最小レプリカ数を`0`**に設定（ADR-018。コスト優先でコールドスタートを許容）
11. Container Apps組み込みの「認証」（Easy Auth）は設定しない。公式イメージが
    `--transport http`起動時に手順6の環境変数を使って自前でEntra ID受信認証を行うため、
    プラットフォーム層での追加認証は不要（[ADR-019](../docs/adr-019_mcp-server-builtin-auth.md)。
    当初はEasy Auth（ADR-016）を予定していたが、二重認証になるだけと判明し撤回した）
12. 「タグ」タブで共通タグを入力 → **確認および作成**

---

## 12. Agent A/B/C用 Entra ID App Registration作成（Issue #9, ADR-002, ADR-016）

リソース側App Registration(`app-sre-dev-001-mcp-server`、手順8-1）とKey Vault(`kv-sre-dev-003`)は
作成済みの前提。Agent A/B/Cそれぞれに対して以下を**3回**繰り返す（`<agent>`は`agent-a`/`agent-b`/`agent-c`）。

> **注**: この「Agentごとに個別App Registration+クライアントシークレットを発行する」方式（ADR-002）が
> 最終形として適切かは未検証。Microsoft公式のFoundry連携サンプルは、クライアント側App Registrationを
> 個別に作らず、リソース側App Registrationに定義したApp RoleをFoundry Project/AgentのMicrosoft Entra ID
> （Managed Identity相当）へ直接割り当てる方式を採っている（ADR-019のReview Note参照）。
> 別Issueで見直すまでは、いったん本手順（既存ADR-002方式）で進めてよい。

1. 「アプリの登録」→ **新規登録**
2. **名前**: `app-sre-dev-001-mcp-client-<agent>`
3. サポートされているアカウントの種類: 「この組織ディレクトリのみ」→ **登録**
4. 左メニュー「APIのアクセス許可」→ **+ アクセス許可の追加** → 「自分のAPI」タブ →
   `app-sre-dev-001-mcp-server`を選択 → `user_impersonation`スコープにチェック → **アクセス許可の追加**
5. 同じ画面で **管理者の同意を与えます** をクリック
6. 左メニュー「証明書とシークレット」→ **+ 新しいクライアント シークレット** → 説明・有効期限を設定 → **追加**
   → 表示された**値**（この画面を離れると二度と表示されない）を控える
7. 「概要」画面の**アプリケーション(クライアント)ID**を控える →
   `infra/dev.bicepparam`の`mcpServerAllowedClientAppIds`に追記する
8. Key Vault(`kv-sre-dev-003`)を開く → 左メニュー「シークレット」→ **生成/インポート**
   → **名前**: `mcp-client-secret-<agent>`、**値**: 手順6で控えたシークレット値 → **作成**
   （Foundry Agent側のMCP接続設定でこのシークレットを使う。実際の接続設定はIssue #10で行う）

3つとも完了したら、`app-sre-dev-001-mcp-server`側の「APIのアクセス許可」に3つのクライアントからの
許可が並んでいることを確認しておく。

---

## 補足

- Key VaultはRBAC認証のため、Managed Identityへの`Key Vault Secrets User`ロール付与は
  1.〜4.の手順には含まない（Key Vault自体の作成時にBicepが付与する想定。手動作成時は
  Key Vaultの「アクセス制御(IAM)」から同様に`Key Vault Secrets User`を`id-sre-dev-001`に
  個別付与すること）
- 作成後、リソース名・タグがBicepテンプレートと一致していることを確認しておく。
  GitHub復旧後に同じ値で`az deployment group what-if`を実行すれば「差分なし」になるはず
