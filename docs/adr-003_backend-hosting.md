# ADR-003: Backendのホスティング基盤と言語

- Status: Accepted
- Date: 2026-07-19

## Context

`CLAUDE.md` はBackendの実行基盤・言語を「Node.js/Python等」とだけ記載し未確定だった。
また、Slack連携の方式（Events API配信 vs Socket Mode）によって、常時起動が必要かどうかが
変わってくる。

検討した選択肢:

- A. Azure Functions（HTTPトリガー + Timer Trigger）
- **B. Azure Container Apps (ACA) 上に常駐サーバーを構築**
- C. その他のPaaS（App Service等）

## Decision

**選択肢B** を採用する。

- ホスティング: Azure Container Apps、`minReplicas=1` で常時起動を維持
- 言語: Python
- Slack連携方式: Socket Mode（Slackからの公開HTTPエンドポイントは持たない）

Socket Modeを採用する時点で、Slack側からの接続を待ち受け続けるプロセスが必須になるため、
Azure FunctionsのようなHTTPトリガー型/スケールtoゼロ前提の基盤とは相性が悪く、
常時起動前提のACAを選んだ。言語はPythonを採用者が最も読み書きできることを優先した。

## Consequences

- `CLAUDE.md` 3章にある `POST /api/foundry-chat` 等の「エンドポイント」は、外部公開HTTP
  エンドポイントではなく、同一ACAアプリ内のSocket Modeイベントハンドラとして実装される
  （API Gatewayや公開URLの管理が不要になる）
- ACAは `minReplicas=1` で常時1台起動するため、Azure Functionsの従量課金・スケールtoゼロと
  比較して固定的な稼働コストが発生する
- Agent Cの週次バッチトリガーの実装方式に波及する（[[adr-004_in-process-scheduler]]参照）
