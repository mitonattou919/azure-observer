# 実装インストラクション: Slack × Azure Foundry Agent (Azure MCP Server 統合版)

## 目的
Slack上でAzure関連の申請・相談・定期レポートを提供する。
Foundry Agent Serviceを中核に据え、リソース操作・コスト確認・ドキュメント参照・アップデート確認を
すべて **Azure MCP Server** および **MS Learn MCP** / **MRC (Microsoft Release Communications) MCP**
の3つのMCPサーバーに統合する。個別リソースAPIを都度実装するのではなく、MCP経由のツール呼び出しに寄せる。

## 全体構成
```
Slack (App Home / Slash Command / Block Kit申請フロー)
        │
        ▼
   Backend (Node.js/Python等)
        │
        ▼
  Foundry Agent Service（用途別に複数Agentを分離）
        ├─ Agent A: 相談用（読み取り専用）
        │     Tools: MS Learn MCP / MRC MCP / Azure MCP(read-only scope)
        ├─ Agent B: 申請フロー用（限定的な書き込み）
        │     Tools: Azure MCP(操作系スコープ、要承認)
        └─ Agent C: 定期バッチ用
              Tools: Azure MCP(read-only) / MRC MCP
```

## 前提条件
- Azure Foundryプロジェクトが作成済みで、Agent Serviceが有効なこと
- Slack Appが作成済みで、App Home / Slash Command / Block Kit申請フローが動作していること
- Azure MCP Serverを自己ホストする環境（Azure Container Apps等）が用意できること
- Managed Identity（User-Assigned推奨）を作成済み、または作成可能であること

## タスク一覧

### 1. Azure MCP Server のデプロイと認証設定
- Azure MCP Serverを自己ホスト構成でデプロイする（Container Apps等）
- 認証はシークレットレスで構成する:
  - User-Assigned Managed IdentityをMCPサーバーにアタッチ
  - 環境変数 `AZURE_MCP_INCLUDE_PRODUCTION_CREDENTIALS=true` を設定し、
    Workload Identity / Managed Identity経由の認証チェーンを有効化する
  - クライアント側からMCPサーバーを呼ぶ経路は別途Entra ID認証（App Registration）で保護する
    （「誰がMCPサーバーを呼べるか」と「MCPサーバーがAzureに対して何をできるか」を分離する）
- Managed IdentityにAzure側でRBACロールを付与する。Agentの用途ごとに最小権限で分ける:
  - 相談・バッチ用Identity: `Reader` ロールのみ
  - 申請フロー用Identity: 対象操作に必要な最小ロール（例: VM起動停止のみなら `Virtual Machine Contributor` を対象リソースグループに限定して付与。サブスク全体には付与しない）

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
  - `POST /api/foundry-chat` … Agent Aへの相談チャット用（App Home）
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
- **App Home（Agent A用）**
  - チャット履歴表示エリア、メッセージ入力、送信ボタン
  - 返信は `section` ブロック本文＋`context` ブロックで参照リンク表示
- **申請フロー（Agent B用、既存Block Kit申請フローを流用）**
  - コスト確認・VM起動停止の申請は既存フロー通り
  - Azure MCP統合後は、バックエンドの実装先が個別API呼び出しからAgent B経由のMCPツール呼び出しに変わる点のみ注意
  - 書き込み系操作は申請→承認→実行の3ステップを維持し、承認ボタン押下後にAgent Bへ実行リクエストを送る
- **定期レポート通知（Agent C用）**
  - ヘッダー「今週のAzure Updates対応チェック」＋対象期間
  - リソースごとにセクションブロック（リソース名/種別、影響度バッジHigh/Medium/Low、推奨対応、参照リンク）
  - 該当ありの場合のみ通知
  - 「詳細を相談する」ボタンでAgent A（App Homeチャット）に文脈を引き継げるようにする（余力があれば）

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
- 二重防御を徹底する:
  1. Foundry側 allowed_tools でAgentごとに呼べるツールを絞る
  2. Managed IdentityのAzure RBACで実行時の権限範囲を絞る（Agentが誤って許可外のツールを呼んでもAzure側で弾かれる）
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
