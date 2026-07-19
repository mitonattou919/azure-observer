# ADR-004: Agent C定期バッチのトリガー方式

- Status: Accepted
- Date: 2026-07-19

## Context

`CLAUDE.md` 5章はAgent Cの週次バッチについて「スケジューラ（Timer Trigger等）」を想定していたが、
これはAzure Functions前提の書き方であり、[[adr-003_backend-hosting]] でACA常駐アプリに
決定したことで実装方式の見直しが必要になった。

検討した選択肢:

- **A. ACAアプリ内蔵のスケジューラライブラリ（`APScheduler`等）でプロセス内バックグラウンドタスクとして実行**
- B. 別途Container Apps Jobs（Scheduled Jobs）を用意し、週次で専用ジョブを起動
- C. Logic Apps等の外部スケジューラからACA内部エンドポイントをHTTPで叩く

## Decision

**選択肢A** を採用する。Slack Bolt (Socket Mode) のイベントループと同一プロセス内で、
`APScheduler` 等を用いて週次cronジョブをバックグラウンドタスクとして実行する。
追加のAzureリソースは作成しない。

## Consequences

- インフラ構成が増えず、[[adr-003_backend-hosting]] で決めたACA 1本構成のまま完結する
- ACAが再起動・再デプロイされた場合、プロセス内蔵のスケジューラ状態もリセットされるため、
  実行タイミングが多少ずれる可能性がある。`minReplicas=1` 固定運用である限り実害は小さいと判断し許容する
- 将来的にバッチの信頼性要件が上がった場合は、選択肢B（Container Apps Jobs分離）への
  移行を検討する

## Review Note (2026-07-19)

PRレビューにて、ACAがマルチレプリカ化した場合にAPSchedulerが重複実行される懸念
（冪等性担保やTable Storageによる簡易ロック機構の導入）を指摘された。
本フェーズでは `minReplicas=1` 固定運用を前提としているため、当該リスクは受容し、
本ADRの決定（選択肢A）を変更しない。マルチレプリカ運用へ移行する際は、
本ADRをsupersedeする形で冪等性担保の設計を別途起こすこと。
