# ADR-014: Agent B初期スコープの操作一覧・MCPツール・RBAC・承認境界

- Status: Accepted
- Date: 2026-07-19

## Context

Issue #4。Agent B（申請フロー）が本フェーズで対応する具体的な操作一覧が未確定だった。
`CLAUDE.md` 2章は「VM起動停止等」とだけ例示しており、以下が詰め切れていなかった:

- VM起動停止以外に含める操作
- 操作ごとに必要なAzure MCPツール・RBACロール
- `ask every time`（承認必須）対象の線引き

調査の結果、Azure MCP Serverの実際のツール仕様には以下の制約・注意点があることが判明した:

- VMの電源操作は `azmcp vm power state` という**単一ツール**に集約されており、
  `power-action` パラメータで `start` / `stop` / `deallocate` / `restart` を切り替える。
  Foundry Agent Serviceの `allowed_tools` はツール単位の許可制御であり、パラメータ値単位
  （例: startのみ許可）では制御できない
- `stop` はOSをシャットダウンするのみでコンピュートリソースは解放されず、**課金は継続する**。
  課金を止めるには `deallocate` が必要（両者は別物であり、コスト目的の停止では`deallocate`が
  本来の目的に合致する）
- Azureの組み込みロールに「VM起動/停止/deallocateのみ」に絞ったものは存在しない。
  最小権限を狙う場合はカスタムロールの自作が必要（`Microsoft.Compute/virtualMachines/start/action`
  等を個別指定）。`Virtual Machine Contributor`（`CLAUDE.md` 1章の例示ロール）はVM作成・削除・
  リサイズ・拡張機能変更まで含む広い権限

## Decision

### 操作一覧（本フェーズ）

VMの **起動（start）** と **停止（deallocate）** の2操作のみとする。`restart` および
素の `stop`（コンピュートリソース非解放）はスコープ外とする。

### MCPツールとUI

- バックエンドは単一ツール `azmcp vm power state` を、Slack申請フローからは常に
  `power-action=start` または `power-action=deallocate` を指定して呼び出す
- `restart` / `stop`（素の停止）は技術的にはこのツール経由で呼び出し可能な状態が残るが、
  Slack UI（App Homeボタン・申請モーダル）上はユーザーに選択肢として提示しない。
  Agent Bのinstructionsにも「ユーザーが依頼した操作以外は行わない」旨を明記するが、
  これはUX上の誤操作防止であり、セキュリティ境界としては扱わない
  （ツール粒度の制約上、`allowed_tools`だけでは`start`/`deallocate`以外を技術的に排除できない
  ことを受容する。[[adr-001_mcp-server-topology]]がすでに受容した
  「`allowed_tools`誤設定が直接事故に繋がる」リスクの延長線上の判断）
- App Homeのボタンは「VM起動申請」「VM停止申請」の2つに分け、それぞれ別モーダルを開く
  （申請ごとに使い捨てスレッドを作る方針は[[adr-011_agent-thread-separation]]のまま）

### RBACロール

対象リソースグループに限定して、組み込みロール **`Virtual Machine Contributor`** を付与する。
カスタムロール（start/deallocate限定）も検討したが、運用・保守コストを優先し本フェーズは
組み込みロールを採用する。

### 承認境界

start / deallocate の**両方**を `ask every time`（承認必須）とする。startとdeallocateの間で
承認要否を区別しない。理由は `CLAUDE.md` 6章が操作の性質（書き込み系・破壊的操作）で一律に
承認必須と定めており、Azure MCPツール注釈上も両アクションとも `Destructive: true` で
区別されていないため。

## Consequences

- Issue #14（Agent B申請フロー機能の実装）は、上記2操作・2モーダル・
  `Virtual Machine Contributor`ロール・両操作承認必須を前提に実装する
- `Virtual Machine Contributor`はVM削除・リサイズ等も技術的に可能な権限を持つため、
  `allowed_tools`の設定ミスがあった場合のブラスト半径は「対象リソースグループ内のVM運用全般」
  まで広がりうる（[[adr-001_mcp-server-topology]]が受容したリスクの範囲内）
- 将来、最小権限を厳密化する場合はカスタムロールへの移行を検討する
  （本ADRをsupersedeする形で別途起こすこと）
- restart・素のstop・その他のVM操作（作成/削除/リサイズ等）を含めるかどうかは、次フェーズ以降の
  スコープ拡張として再検討する

## Review Note (2026-07-20)

Issue #30にて、`microsoft/mcp`のコマンドリファレンス（azmcp-commands.md）と実際のMCPサーバー
`tools/list`を突き合わせた結果、VM電源操作ツールの正式名は **`azmcp compute vm power-state`**
（namespace: `compute`、`--power-action start|stop|deallocate|restart`）であることを確認した。
本ADR冒頭に記載していた`azmcp vm power state`という表記は誤りであり、本ノートをもって訂正する。
Decision（操作一覧・RBAC・承認境界）自体への変更はなし。[[adr-021_mcp-tool-names-and-namespace]]も参照。
