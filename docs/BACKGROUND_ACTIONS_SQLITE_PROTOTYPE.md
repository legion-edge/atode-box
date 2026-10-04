# PR A extracted validation boundary

Current A: analysis and all151 tests passed. Counts117/154 below describe earlier prototype snapshots on the original working branch; they are not this extracted branch's suite total. Native admission/runtime and later Android acceptance are outside A. See [A contract](SHARED_ACTION_STORAGE_CONTRACT.md).

# 通知actionのSQLite prototype検証

2026-10-04 JST。Issue #40 / Draft PR #41の先行実装。最新main `e474602dace37d42404e710bc6519cdd22634637`を起点とし、PR #38の未merge変更を含めない。

## 今回の範囲

`lib/storage/sqlite_action_transactions.dart`は、注入されたDatabaseFactory・明示pathだけで開く実験adapterである。既存のv2 parser / reducer / `prepareBackgroundAction`を匿名DBへ接続して試験した。productionのLocalRepository、FileDocumentStore、既存JSON正本、UI、通知port、payload発行、native channel、manifest、foreground action設定は変更しない。端末・インストール・保存item・通知予約・権限・未保存入力への操作は行っていない。

DBには匿名record/settingsのJSON正本1行とdocument revision、別表のeffects outbox revisionを保存する。seedは明示fixtureのみ・既存正本があれば無変更であり、実JSONの読込・移行・fallbackはない。epoch/incarnationは注入値であり、生成・復元検出を実装したものではない。

CASはBEGIN IMMEDIATEのtransaction内で最新document・全previous recordを再照合し、対象itemだけを更新する。item・generation consume・revision増加・outboxは同時commitする。不一致はwriteなし。prototypeのtitle編集とsettings保存も最新正本へ適用するが、これらは実アプリの全writer移行やsettings変更時のschedule再計算を代替しない。

terminal generation `9007199254740991`は保存できるがpayloadとして受理しない。最後の受理可能generationをconsumeして以降の再受理を防ぐ。破損schema、item ID重複、通知ID重複、不正identityはwrite前に拒否する。

outbox ackはrevision一致時だけ消す。古いackが新しいdirty状態を消すことはない。これはOS側の古いcancel/scheduleを止めるnative gateではない。過去予定のdelivery方針も選んでおらず、outboxを時刻だけで自動破棄しない。

## 依存とbusy対策

- `sqflite_common: ^2.5.13`（解決2.5.13）: platformに依存しないDatabaseFactory / transaction API。native DB pluginは今回追加しない。
- dev依存 `sqflite_common_ffi: 2.3.7`と`sqlite3: ^2.9.4`（解決2.9.4）: Windows匿名実DB試験。v3 build hooksによる新規native buildを避ける公式v2構成。追加解決依存は`synchronized 3.4.2`。
- FFIの別connectionは同じisolateを使う構成であり、同期busy_timeout待機が競合connectionのcommitを妨げた。初回20並行試験とbarrier試験はこの理由で失敗し、成功として扱わなかった。
- 修正後はbusy_timeout=0、BEGIN IMMEDIATE。SQLITE_BUSYのみ、transaction callbackが未開始の場合に最大40回・間隔10msでyieldする。callback開始後・commit・rollbackの例外は再実行しない。read-only操作もBUSYだけ上限付き再試行する。これはnative OS gateやAndroid/iOS engine間の証明ではない。

公式資料（2026-10-04確認）: [sqflite_common API](https://pub.dev/packages/sqflite_common)、[FFI 2.3.7](https://pub.dev/packages/sqflite_common_ffi/versions/2.3.7)、[v2/v3構成](https://pub.dev/packages/sqflite_common_ffi/versions/2.4.3)、[SQLite transaction](https://www.sqlite.org/lang_transaction.html)。FFI資料のmulti-instance supportはsimulatedとされている。

## 実施した検証

`flutter analyze`: 問題なし。`flutter test`: 全117件成功（既存main 96件、pure action 11件、今回実DB 10件）。

実DB試験は`test/sqlite_action_transactions_test.dart`。各testで自身が生成した匿名一時directory内のファイルDBを使用し、`singleInstance:false`で別connectionを開く。

| 条件 | 確認結果 |
| --- | --- |
| 20重複・同一予定時刻 | consumeとcount増加は1回だけ、他item保全 |
| 同snapshot barrierでcomplete / snooze | 最初のcommitだけ受理、revision/generationは1増加 |
| title/settings競合 | CAS再読込で最新metadata/settingsと他itemを保持 |
| outbox INSERT triggerのabort | document/item/count/generation/revisionをrollback、outboxなし |
| commit後close/reopen | consume・dirty revision持続、重複再受信は無変更 |
| stale ack | 新revisionのdirty状態を消さない |
| seedと未知schema | 初期化は既存正本を上書きせず、未知schemaも保存し直さない |
| previous token不一致 | 同revisionでもwriteなし |
| writer lock保持 | 上限到達で失敗、無変更、lock解除後の操作は成功 |
| generation上限 / 通知ID重複 | terminal consume可能、terminal payload拒否、破損重複は無変更 |

独立レビューと再レビューを実施。generation上限・読込時通知ID重複のP2指摘を修正し、再レビューで重大な追加指摘なし。unit / Windows FFI結果であり、process強制終了、実Android/iOS engine、OS予約・到達・音・振動・lockscreenを試験したものではない。追加OSビルド・実機インストール・GitHub CIはこのローカル準備では未実施。新規Gradle cacheは作らない。

## 未解決・有効化の停止条件

Issue #40と[設計の必須条件](BACKGROUND_ACTIONS_DESIGN.md#独立設計レビュー結果有効化を止める条件)を維持する。

続くコード調査・独立設計レビューと副作用のない回復判定は[回復設計レビュー](SHARED_ACTION_STORAGE_CONTRACT.md)を参照する。期限超過・旧通知移行の本人判断と、native gate/復元の技術的証明を分けて記録する。

1. 予定超過outboxの配信方針とOS受付／実到達の区別。
2. backup復元ABA、復元されないmarker、epoch更新と旧予約無効化。
3. engine破棄・OS応答喪失・再起動でも古いOS処理を残さないnative gate。
4. 旧future / late pending / displayed / unknown通知の移行と本人向け説明。
5. 実JSON v0/v1保全移行とdowngrade分岐、全foreground writer移行、UI再読込、native DB factoryとheadless plugin登録。

上記を解消する前にproduction保存を置換したり、完了／あとでのforeground設定を外したりしない。Issue完了・実機受入・merge可能とは報告しない。PR #41更新時は「pure契約＋SQLite prototypeの匿名検証」までとし、Draft・Issue参照のみを維持する（Closes #40を付けない）。公開範囲とCI/OSビルド実行の扱いは親へ報告してから決める。
