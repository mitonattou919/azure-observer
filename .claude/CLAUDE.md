# 実装インストラクション: Slack × Azure Foundry Agent (Azure MCP Server 統合版)

## 目的
Slack上でAzure関連の申請・相談・定期レポートを提供する。
Foundry Agent Serviceを中核に据え、リソース操作・コスト確認・ドキュメント参照・アップデート確認を
すべて **Azure MCP Server** および **MS Learn MCP** / **MRC (Microsoft Release Communications) MCP**
の3つのMCPサーバーに統合する。個別リソースAPIを都度実装するのではなく、MCP経由のツール呼び出しに寄せる。

## 全体構成
```
Slack (App Home[ダッシュボード] / DM / 「sre」チャンネル@メンション / Block Kit申請フロー / 「sre」チャンネル[承認・定期通知])
        │
        ▼
   Backend (Node.js/Python等)
        ├─▶ Azure MCP（読み取り、Agent非経由。App Homeダッシュボード用のコスト最適化推奨・
        │     サービス正常性イベントを定期キャッシュ。ADR-021）
        │
        ▼
  Foundry Agent Service（用途別に複数Agentを分離）
        ├─ Agent A: 相談用（読み取り専用。DM/「sre」チャンネル@メンションごとに別スレッド）
        │     Tools: MS Learn MCP / MRC MCP / Azure MCP(read-only scope)
        ├─ Agent B: 申請フロー用（限定的な書き込み。申請ごとに使い捨てスレッド）
        │     Tools: Azure MCP(操作系スコープ、要承認)
        └─ Agent C: 定期バッチ用
              Tools: Azure MCP(read-only) / MRC MCP
```

チャット導線・チャンネル構成・スレッドモデル・App Homeのデータ取得方式の詳細な決定背景は
[ADR-010](../docs/adr-010_slack-entry-points-and-channel-routing.md) 〜
[ADR-012](../docs/adr-012_app-home-data-source.md) を参照。

## 前提条件
- Azure Foundryプロジェクトが作成済みで、Agent Serviceが有効なこと
- Slack Appが作成済みで、App Home / Slash Command / Block Kit申請フローが動作していること
- Azure MCP Serverを自己ホストする環境（Azure Container Apps等）が用意できること
- Managed Identity（User-Assigned推奨）を作成済み、または作成可能であること

## タスク一覧

### 1. Azure MCP Server のデプロイと認証設定
- Azure MCP Serverを自己ホスト構成でデプロイする（Container Apps。[ADR-018](../docs/adr-018_mcp-server-container-apps-config.md)）
  - コンテナイメージは組織共通のAzure Container Registryを使う。プロジェクト固有のACRは作らない
    （[ADR-017](../docs/adr-017_shared-acr-and-image-delivery.md)）。ビルド・pushはCI化せず手動運用とする
  - Ingressはexternal（インターネット到達可能）とし、Entra ID認証（Easy Auth）で保護する。
    VNet閉域化はこのフェーズでは行わない（[ADR-016](../docs/adr-016_mcp-server-inbound-auth.md)）
- 認証はシークレットレスで構成する:
  - User-Assigned Managed IdentityをMCPサーバーにアタッチ
  - 環境変数 `AZURE_MCP_INCLUDE_PRODUCTION_CREDENTIALS=true` を設定し、
    Workload Identity / Managed Identity経由の認証チェーンを有効化する
  - クライアント側からMCPサーバーを呼ぶ経路は、Container Apps組み込みのEasy Auth（`authConfig`）で
    保護する。MCPサーバー本体（公式イメージ）には手を入れない
    （「誰がMCPサーバーを呼べるか」と「MCPサーバーがAzureに対して何をできるか」を分離する）。
    クライアントはFoundry Agent A/B/Cに加え、App Homeダッシュボード用にAzure MCPを直接呼ぶ
    Backend自身も含む（ADR-012）
  - Entra ID App Registrationは用途で作成Issueが分かれる: MCPサーバー自身を表す**リソース側**と
    **Backend用クライアント側**はIssue #8で作成し、**Agent A/B/C用クライアント側**（3つ）は
    Issue #9で作成する（[ADR-016](../docs/adr-016_mcp-server-inbound-auth.md)）
- Managed IdentityにAzure側でRBACロールを付与する（※ [ADR-001](../docs/adr-001_mcp-server-topology.md)により、
  Identityは用途別に分けず単一構成とする。Agentごとの権限差はManaged Identity側ではなく
  Foundry側の `allowed_tools` で制御する）:
  - `Reader` ロールを付与し、加えて申請フロー用の操作に必要な最小ロール
    （例: VM起動停止のみなら `Virtual Machine Contributor`）を対象リソースグループに限定して
    同一Identityに付与する。サブスク全体への書き込みロール付与は行わない

### 2. Foundry Agent の分離設計
用途ごとに **別Agent** を作成し、ツールとallowed_toolsを分離する。1つのAgentに全権限を持たせない。

| Agent | 用途 | 接続MCP | allowed_toolsの方針 |
|---|---|---|---|
| Agent A（相談） | Azure相談チャット(App Home) | MS Learn MCP, MRC MCP, Azure MCP | 読み取り系ツールのみ許可 |
| Agent B（申請フロー） | コスト確認/VM起動停止等の申請実行 | Azure MCP | 対象操作ツールのみ許可、書き込み系は `ask every time`（承認必須） |
| Agent C（定期バッチ） | リソース×アップデート突合レポート | Azure MCP(read-only), MRC MCP | 読み取り系ツールのみ許可 |

- 各Agentのinstructions（システムプロンプト）に共通で明記すること:
  - 「許可されていない操作は行わず、権限不足の場合はその旨を伝えること」
  - 「推測で断定せず、MCPツールの結果に基づいて回答すること」
- Agent A instructions個別の追記:
  - 「Azureの使い方・仕様に関する質問にはMS Learn MCPを使うこと」
  - 「最新アップデート・非推奨予定に関する質問にはMRC MCPを使うこと」
  - 「リソースの現状確認にはAzure MCPの読み取りツールを使うこと」
  - 「回答の最後に参照したドキュメント/アップデートのリンクを付けること」

### 3. Backend API の実装
- エンドポイント例:
  - `POST /api/foundry-chat` … Agent Aへの相談チャット用（DM／「sre」チャンネル@メンション）
  - `POST /api/foundry-request` … Agent Bへの申請実行用（Block Kit申請フロー）
  - スケジューラから呼ぶ内部処理 … Agent Cのバッチ実行用（HTTPエンドポイント不要、Timer Trigger内で直接呼び出し可）
- 共通処理:
  1. `threadId` が無ければ新規スレッドを作成
  2. 対象Agentにメッセージ/リクエストを送信
  3. MCPツール呼び出し（何のツールを何の引数で呼んだか）を全て監査ログに記録
  4. 書き込み系ツール呼び出しが承認待ちになった場合、Slack側に承認ボタン付きメッセージを出す
  5. レスポンステキスト・参照リンクをSlack返却用に整形
- スレッド状態はユーザーごとに永続化（DBまたはKVS。ユーザーID→threadIdのマッピング）
- エラーハンドリング: Foundry/MCP呼び出し失敗時はSlackにエラーメッセージのみ返す（内部エラー詳細は出さない）

### 4. Slack UI の実装
（画面構成・チャネルルーティングの決定背景は
[ADR-010](../docs/adr-010_slack-entry-points-and-channel-routing.md) 〜
[ADR-012](../docs/adr-012_app-home-data-source.md)、
表示データの中身は[ADR-021](../docs/adr-021_mcp-tool-names-and-namespace.md)を参照）

- **App Home（ダッシュボード。チャットUIではない）**
  - コスト最適化推奨事項一覧（Azure Advisor、`--category Cost`）、サービス正常性イベント一覧
    （Azure ResourceHealth）を表示。Azure MCPに実際の当月消費額・発火中アラートを返すツールが
    存在しないため、これらを代替指標として採用している（ADR-021）。Foundry Agentを経由せず、
    Backendが Azure MCPの読み取りツールを直接呼び出し、定期キャッシュした値を表示する（ADR-012）
  - VM起動申請ボタン（押下でAgent B申請モーダルを開く）
  - JIT権限付与のプレースホルダー（将来機能。実装が無い段階でも導線のみ表示）
- **Agent Aとの質問（DM／「sre」チャンネル@メンション）**
  - Slack App Homeの `Home` タブは `input` ブロックを常設した継続的な会話UIに向かないため、
    チャット入力はApp Homeに置かず、DMまたは「sre」チャンネルでの@メンションで受け付ける。
    他チャンネルでの@メンションは正式導線としてサポートしない
  - DMとsreチャンネル@メンションは別々の会話文脈（スレッド）として扱う（ADR-011）
  - 返信は `section` ブロック本文＋`context` ブロックで参照リンク表示
  - `/reset`相当のコマンドは、発行した場所（DMまたはsreチャンネル）のスレッドのみをリセットする
- **申請フロー（Agent B用、App Homeボタン起点で新規設計）**
  - リポジトリ・社内に既存の実体は無いため、モーダル項目を含めて本フェーズで新規に設計する
    （対応する具体的な操作一覧・必要なMCPツール/RBACロールはIssue #4で確定）
  - バックエンドの実装先は個別API呼び出しではなくAgent B経由のMCPツール呼び出しとする
  - 書き込み系操作は申請→承認→実行の3ステップを維持し、承認ボタン押下後にAgent Bへ実行リクエストを送る
  - 申請ごとに使い捨てのFoundryスレッドを作成する。Agent Aの相談スレッドとは共有しない（ADR-011）
- **「sre」プライベートチャンネル（承認・定期通知、Agent B/C共用）**
  - 承認: 申請内容と承認/却下ボタンを投稿。チャンネル参加＝承認権限とみなすため、
    パブリックチャンネルにはせず、招待は運用でSRE室メンバーに限定する
  - 定期通知（Agent C）: ヘッダー「今週のAzure Updates対応チェック」＋対象期間、
    リソースごとにセクションブロック（リソース名/種別、影響度バッジHigh/Medium/Low、推奨対応、参照リンク）、
    該当ありの場合のみ通知
  - 「詳細を相談する」ボタンでAgent A（DM／@メンション）に文脈を引き継げるようにする（余力があれば）

### 5. 定期バッチ処理（Agent C）の処理フロー
- 実行トリガー: スケジューラ（Timer Trigger等）で週次実行
- 処理:
  1. Azure MCPの読み取りツールで対象サブスクリプションのリソース一覧（種別・SKU・リージョン）を取得
  2. MRC MCPで直近1〜2週間分のAzure Updatesを取得
  3. 両方をAgent Cに渡し、影響度判定・要約をさせる
     - 非推奨(Deprecation)・破壊的変更(Breaking Change)は必ずHighに分類させる
     - 関係の薄いアップデートは除外させる
     - 根拠となるアップデート内容を明記させ、推測で断定させない
  4. 該当ありの場合のみSlack通知

### 6. 権限・セキュリティ（まとめ）
- 権限制御はFoundry側 `allowed_tools` によるAgentごとのツール制限を主防御とする。Managed Identityは
  単一構成（[ADR-001](../docs/adr-001_mcp-server-topology.md)）のため、Azure RBACは`allowed_tools`から
  独立した第二の防御層としては機能しない点に留意する（受容済みリスク。将来的にAgent用途別の
  MCPサーバー分離を再検討する余地あり）
- 書き込み系・破壊的操作ツールは `ask every time`（承認必須）に設定
- MCPサーバー自体へのアクセスもEntra ID認証で保護し、誰でも叩ける状態にしない
- Slack Bot Token, Foundry API キー等はSecrets管理(環境変数 or Key Vault)に格納
- 全MCPツール呼び出しを監査ログに記録（誰が・いつ・どのAgentが・何のツールを・どんな引数で）

### 7. テスト観点
- Agent Aがread-onlyツールのみ使い、書き込み系ツールを一切呼べないこと
- Agent Bの書き込み系操作が承認フローを経由しないと実行されないこと
- Managed IdentityのRBACを絞った状態で、許可範囲外のリソースに対する操作がAzure側で拒否されること
- MS Learn MCP / MRC MCP / Azure MCPの呼び分けが指示通り機能すること
- 定期バッチが該当アップデートありの週だけ通知し、根拠リンク付きで要約されること
- 各MCP/Foundry API障害時にSlack側がクラッシュせずエラーメッセージを表示すること

## 成果物
- Azure MCP Serverのデプロイ設定（Managed Identity構成含む）
- Foundry Agent A/B/C の設定（instructions, allowed_tools, MCP接続設定）
- Backend実装コード一式
- Slack Block Kit定義（App Home / 申請フロー / 定期通知）
- Managed Identity・RBAC設定のREADME
- 簡易動作確認手順書
