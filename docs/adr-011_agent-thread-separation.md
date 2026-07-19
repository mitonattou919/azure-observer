# ADR-011: Foundryスレッドモデルの見直し（Agent A入口別・Agent B使い捨て）

- Status: Accepted
- Date: 2026-07-19
- Supersedes: [[adr-008_thread-lifecycle]]

## Context

[[adr-008_thread-lifecycle]]は「ユーザーID→`threadId`」の1対1マッピングを前提とし、
Agent AとAgent Bで`threadId`を共有する方針だった（当時のレビューで文脈混在の懸念は指摘されたが、
シンプルさを優先し据え置かれていた）。

[[adr-010_slack-entry-points-and-channel-routing]]により、以下の変更が生じた。

- Agent Aへの質問導線がDMと「sre」チャンネル@メンションの2つに増えた
- Agent Bの入口がApp Homeのモーダル送信になり、複数ターンの会話ではなく「申請1件＝1回完結の処理」
  という性質が明確になった

この2点により、ADR-008の前提（ユーザーごとに単一のthreadIdを使い回す）をそのまま維持すると、
以下の問題が生じる。

- DM（1:1のプライベートな聞き方）で話した内容が、Agent生成時にsreチャンネル（複数人が見る場）での
  回答に意図せず滲み出るリスクがある
- Agent Bには会話を継続する概念が無いため、Agent Aの相談用スレッドと共有する意味が無く、
  むしろ申請処理のログが相談文脈に混入する

## Decision

スレッドは `(user_id, entry_point)` 単位で分離して管理する。

| entry_point | スレッドの扱い |
|---|---|
| Agent A - DM | ユーザーごとに1スレッドを継続利用（[[adr-008_thread-lifecycle]]の30日自動リセット・`/reset`は踏襲） |
| Agent A - 「sre」チャンネル@メンション | ユーザーごとに1スレッドを継続利用。DM用スレッドとは別管理 |
| Agent B - 申請フロー | 申請（Run）ごとに使い捨てのスレッドを新規作成する。永続的なマッピングは持たない |

- `/reset`相当のコマンドは、**発行された場所のスレッドのみ**をリセットする
  （DMで発行すればDM用スレッドのみ、sreチャンネルで発行すればsreチャンネル用スレッドのみ）
- 30日操作なしでの自動リセット判定（[[adr-008_thread-lifecycle]]）は、entry_pointごとの
  `chat_turn`レコードの最終利用日時を基準に個別に行う
- [[adr-005_storage-and-activity-log]]で定義したスレッドマッピングのキーを
  `user_id → threadId` から `(user_id, entry_point) → threadId` に変更する。Agent Bは
  使い捨てのため永続マッピングテーブルには書かず、実行時に生成した`threadId`を
  `activity_log`の`tool_call`/`chat_turn`レコードに記録するのみとする

## Consequences

- DMでの相談内容がsreチャンネルに滲み出るリスクを防げる。Agent Bの処理ログがAgent Aの
  相談文脈に混入することも無くなる
- ユーザー視点では「DMで聞いた内容の続きをsreチャンネルでは聞けない」という不便が生じるが、
  そこまで文脈の継続性が重要な質問は多くない、という判断のもとで許容する
- Agent Bはスレッドの永続化・クリーンアップが不要になり実装がシンプルになる一方、
  申請のたびにスレッド作成のAPI呼び出しが1回増える（軽微なオーバーヘッド）
- [[adr-005_storage-and-activity-log]]のスレッドマッピングのデータモデル（PartitionKey/RowKey設計）
  を本ADRの決定に合わせて更新する必要がある
- 本ADRは[[adr-008_thread-lifecycle]]をsupersedeする。ADR-008の30日自動リセット・手動`/reset`という
  基本方針自体は変更せず、適用単位のみを見直したものである
