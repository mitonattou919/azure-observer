---
name: slack-app-design-grilling
description: Interview the user about Slack app UI/UX decisions (Block Kit screens, entry points and channel routing, OAuth Scopes) when their own knowledge of Slack platform constraints is incomplete. Use for Slack app design sessions — App Home, DM vs channel routing, approval/notification channel design, scope selection — especially early in a project before screens are built.
---

# Slack App設計グリリング（素案）

`grilling` スキルの「1問ずつ、推奨案付きで、設計ツリーを掘り下げる」という基本ループを土台に、
Slack Block Kit / OAuth Scopes 特有の落とし穴を埋めるための特化版。Issue #2（Slack画面設計）の
グリリングセッションから抽出した素案であり、まだ実運用で検証されていない。

## 使うべき場面

- Slack App（Block Kit画面、チャンネル/DM構成、OAuth Scopes）を設計する会話で、
  依頼者自身がSlack Platformの技術的制約（Home tabの制約、スコープの種類 `im:*`/`channels:*`/
  `groups:*`、チャンネル可視性の意味など）を正確に把握していない場合
- 画面構成の決定が権限モデル・セキュリティに波及する場合（Slackでは「誰がそのチャンネルに
  入れるか」がしばしばそのまま権限境界になるため、UI設計とセキュリティ設計が不可分）

## 基本ループ（`grilling` を継承）

- 質問は1問ずつ。前の質問への回答を待たずに次へ進まない
- 各質問には推奨案とその理由を添える
- コードベース（既存実装・既存ドキュメント）で答えが分かることは、聞かずに調べる

## Slack特有に追加する責務

### 1. 選択肢を出す前に、Slackの制約を先に説明する

依頼者は「Slackで何ができるか」を正確に知らないことが多い。「どうしますか？」とだけ聞くと、
存在しない選択肢（例: Home tabに常設のチャット入力欄を置く）を前提に議論が進んでしまう。
選択肢を提示する前に、関連するSlack Platformの制約を一言で説明してから選択肢に入ること。

例（今回の実例）: 「Slack Home タブは `views.publish` で全体を都度再描画する方式で、通常の
メッセージ入力欄のような継続的な会話UIには不向き」という制約を先に説明した上で、
DM／チャンネル@メンション／App Home常設入力、の3案を出した。

### 2. UI/導線の決定を、必ず権限モデルに接続して確認する

Slackでは「そのチャンネル・DMに参加できること」＝「実行できること」になりがちである
（例: 承認チャンネルへの参加＝承認権限）。チャンネル構成・可視性（public/private）・
誰が@メンションできるかを決めるたびに、「この決定は誰が何をできるようになることを意味するか」
を明示的に確認すること。依頼者が意識していない権限昇格経路（例: 通知を見たいだけの人が
承認チャンネルに入って承認権限まで得てしまう、パブリックチャンネルなら誰でも自己参加できる）
を見つけたら、聞かれていなくても指摘すること。

### 3. OAuth Scopesは「送信/受信」「DM/パブリック/プライベート/マルチパーティDM」の
   マトリクスで確認する

`chat:write` のような送信系スコープは会話種別を問わず共通だが、読み取り系スコープは
`im:history`（DM）/ `channels:history`（パブリック）/ `groups:history`（プライベート）/
`mpim:history`（マルチパーティDM）のように会話種別ごとに分かれることが多い。
「このBotはこの会話種別で何を読む必要があるか／送るだけで済むか」を機能ごとに確認し、
不要な読み取りスコープを要求しないこと。正確なスコープ名は年月とともに変わりうるため、
断定的に書かず「実装時にSlack公式ドキュメントで最終確認」と明記すること。

### 4. 「既存フロー」を前提にしない

要件定義書やインストラクションに「既存のBlock Kit申請フローを流用」等と書かれていても、
実際にリポジトリ・社内システムに実体があるとは限らない。画面設計の詳細（モーダル項目等）に
入る前に、それが本当に既存なのか、実質ゼロから設計するのかを確認すること。

### 5. 決定はADR-worthyとして扱い、セッションの最後にまとめて書き起こす

決定が既存ADRの前提を覆す場合は、既存ADRを削除・書き換えず `Status: Superseded by [[new-adr]]`
＋日付付きの補足ノードで残す。ADRの実際の執筆は設計ツリーを一通り詰め切ってからまとめて行い、
質問1つごとにADRを書かない（依頼者に確認した上で進めること。詳細は
[[feedback-adr-workflow]] メモリを参照）。

### 6. セッションの締めに、ラフなBlock Kit Builder用JSONを渡す

テキストでの合意だけでは画面イメージが掴みにくい。設計が収束したら、
https://app.slack.com/block-kit-builder に貼れる粗いJSON（`home` view / メッセージ用 `blocks`）を
画面ごとに用意し、依頼者が視覚的に確認できるようにする。細部の値はダミーで良い。

## 未検証の点（素案として）

- まだ他プロジェクトで使っていないため、上記の「責務」が過不足ないかは要検証
- `grilling` 本体との統合方法（別スキルとして呼ぶか、`grilling` 側にSlack特化の分岐を持たせるか）
  は未決定。現状は独立したスキルとして素案化した
