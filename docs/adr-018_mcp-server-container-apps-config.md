# ADR-018: MCP Server用Container Apps Environmentとスケーリング設定

- Status: Accepted
- Date: 2026-07-20

## Context

Issue #8。Azure MCP ServerをホストするContainer Apps Environmentと、その稼働に必要な
Log Analyticsワークスペース（[[adr-015_monitoring-logging]]によりACA標準ログの収集先として
既に前提とされている）、およびContainer Appのスケーリング設定（`minReplicas`）が未確定だった。

[[adr-003_backend-hosting]]でBackend自身も将来Container Apps上（`minReplicas=1`常時起動）に
載ることが決まっており、Environment・Log Analyticsワークスペースを共有すべきかも論点になった。

## Decision

- **Container Apps Environment**: 組織共通のEnvironmentは存在しないため、`rg-sre-dev-001`に
  新規作成する。Backend用のContainer App（Issue #11で実装予定）が載る際は、この同一
  Environmentを共有する（Environment自体はほぼコストがかからず、リソース分離はContainer App単位
  で十分に行えるため、わざわざ分ける理由がない）
- **Log Analyticsワークスペース**: ACRのような組織共通ワークスペースの存在は本フェーズでは
  確認できておらず、`rg-sre-dev-001`に**新規作成**する。共通化すべきという直感はあるが、
  現時点では確証がないため一旦プロジェクト専用とし、将来共通ワークスペースの存在が確認され次第
  移行を検討する（再検討トリガーは「共通ワークスペースの所在確認ができたとき」）
- **MCPサーバーのContainer App スケーリング**: `minReplicas=0`（ゼロスケール）とする。
  Backendの`minReplicas=1`（常時起動、Socket Modeで接続を維持する必要があるため）とは事情が異なり、
  MCPサーバーはFoundry Agent/Backendからの同期呼び出し時のみ稼働すればよい。コールドスタート
  遅延は許容し、実運用で問題になった場合の**チューニング観点**として残す

## Consequences

- Log Analyticsワークスペースがプロジェクト専用になるため、将来共通ワークスペースが見つかった場合、
  ログの移行・二重運用期間が発生しうる
- `minReplicas=0`により、アイドル後の初回呼び出しでコールドスタート遅延がSlackでのユーザー体感に
  乗る可能性がある。運用上問題になった場合は`minReplicas=1`への変更をチューニングとして検討する
  （ADRのsupersedeは不要な軽微変更として扱ってよい）
- Backend用Container App（Issue #11）は本ADRで作成するEnvironmentを再利用する前提になるため、
  Issue #11実装時に本ADRを参照すること
