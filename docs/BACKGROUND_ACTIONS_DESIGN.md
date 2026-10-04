## 背景・既存Issueとの関係

利用者の希望: 通知の「完了」「あとで」はアプリ画面を開かず反映する。「開く」と通知本文tapは引き続き画面を開き、activeを維持する。

2026-10-04 JSTに全既存Issueと#7/#19を確認した。#7はOS通知と3アクションの接続を完了済み、#19は文面・量・配信方式の広い改善である。本IssueはUIを起動しない2アクションと、そのために必要な永続化・競合対策に限定する。関連: #7、#19、#3、#21。起点main: b19c84fd7c2d8693305dcf2e731e3a1a369d2d51。

## Scope / 対象外

- Android/iOSのbackground callbackをUIから分離し、最新保存状態に対する完了／あとでを1回だけ確定する。
- 全foreground/background writerの排他・atomic永続化、payload世代照合、OS予約との失敗回復、匿名競合テスト。
- 対象外: 通知本文プレビューの変更、クラウド・認証・新しい権限要求・exact alarm化・通知から削除。実機APK/予約/権限変更、merge、リリースも本設計段階では行わない。

## 現状の阻害点

- FlutterNotificationPortは3アクション全部をforeground設定にしており、background callback未登録。
- LocalRepository._tailは同一インスタンス内だけ。_loadはキャッシュ済み状態を再利用し、FileDocumentStoreは共通.tmp/.bakで文書全体を書き換える。別engineのwriterが加わると更新喪失／一時ファイル衝突が起こりうる。
- 保存先channelはAndroid MainActivityとiOS implicit UI engineで登録され、headless engineで利用できる保証がない。
- 現payloadはitem ID＋UTC時刻のみ。同一時刻への再計算・ABAを区別できず、世代番号が必要。
- OS通知同期もControllerインスタンス内だけの直列化。保存をtransaction化するだけでは古いsyncが新しい予約を取り消す競合は防げない。

## 推奨設計（提案、まだ実装しない）

### 1. UIを必要としない入口

完了／あとではAndroid showsUserInterface=false、iOS foreground optionを外す。top-level entry-point callbackからUI非依存serviceを呼び、URLやNavigatorへ触れない。「開く」／本文tapは既存のforeground経路を維持する。Androidの既存ActionBroadcastReceiverを利用し、iOSは背景engineへのplugin registrantを登録する。app-private保存先と永続化channelは、Activity/Sceneではなく全engineに登録できるpluginへ移す。

### 2. 保存の単一正本・全writer共通transaction

小さく始める候補はSQLite内の既存JSON snapshot 1行＋document revision＋item通知generation＋effects outbox。既存ドメインのJSON変換・ルールエンジンを維持し、items全正規化を必須にしない。Android/iOSで利用できる既存DB pluginかnative bridgeを選ぶ段階は別レビューとする（dependency未決定）。

BEGIN IMMEDIATE相当で最新snapshotを読み、意図として渡された変更を最新レコードへ適用して、snapshot・revision・generation・outboxを同一transactionにcommitする。busyは上限付き再試行、失敗は保存成功扱いにしない。キャッシュした文書／古いInboxItem全体を後から上書きしない。登録、分類後編集、詳細編集、完了、削除、あとで、生活設定、timezone再計算の全経路を移す。updateItemはpatchまたはexpected revision照合に置換する。UIはresume／commit通知で再読込する。

JSON v0/v1移行は、正本がまだない場合だけ検証済みJSONをtransaction内へ取り込む。二重起動でもimportは1回。未知schema／破損は空データとして上書きしない。旧JSONを残して成功後はDBだけを書き、DBが既存なら旧JSONへ自動fallbackしない。バックアップ／downgrade時の新旧正本分岐は未解決の移行レビュー項目であり、既存ユーザーへの導入前に対策を確定する。

DartのFuture queueやRandomAccessFile.lockだけをcross-isolate排他の根拠にしない。

### 3. 世代照合・連打と競合

新payloadはversion、item ID、notification ID、UTC予定時刻、通知generation、item incarnation／保存系epochだけ（本文／URLなし）。厳密parse後、transaction内でactive・ID・時刻・generation・incarnation・epochを再照合する。削除／完了／再予定された旧generation、未知version、不正actionは無変更。

完了／あとでの受理は同じgenerationをconsumeし、generationを単調増加させてcommitする。あとではsnooze count＋次予定＋context/reasonを同時更新。次予定が偶然同じ時刻でもgenerationが変わるため連打は再適用されない。同じ旧generationに完了とあとでが競合したら最初にcommitした1操作だけが有効。foregroundの保存・設定変更と競合しても、最新stateへのpatchで他item・編集済みmetadataを失わない。

旧payloadは安全な移行境界が必要。通知の完了／あとでは無効として保守的に拒否し、次の通常foreground同期で将来予約をversion付き予約へ置換する案を推奨する（遅配中・過去・不明状態の扱いは下記レビュー条件による）。「開く」／本文tapは既存ID＋時刻＋active照合で読取・UI遷移のみ許可する。旧通知のボタンが一時的に反映されない点は本人受入と移行文書が必要。日時generationを何で更新するか（category変更／同時刻再計算／settings／timezone）を明文化し、content-only編集の扱いもテストする。

同ID再作成・バックアップ復元でgenerationが戻るABAには、item incarnationと保存系epochの照合が必要。epochを復元されないinstall markerと結び付ける候補を検討するが、Android/iOSのbackup設定とmarker消失・再導入検出を実証するまでは安全としない。復元検出時は旧actionを無効化し、旧OS予約を照合して再構築する。単にDB内にUUIDを保存してbackupごと戻す案では対策にならない。

### 4. OS副作用・回復

DBとOS予約は単一transactionにはできない。domain commit時にdesired revisionをoutboxへ保存し、後でOS状態を最新正本へ収束させる。commit前の失敗は変更なし、commit後のOS失敗は保存済み状態を巻き戻さずoutboxを保持する。次のcallback／通常起動・resumeで再試行する。短いbackground実行時間内に完了しなければ、アプリ未起動での再予約を保証したと報告しない。追加の常駐service／新権限は採用しない。

全engineのOS同期をnative process共通coordinatorへ集約し、snapshot読取→cancel/schedule→成功revision記録を直列化する。全writerも同じgateで短いDB commitを行い、古いplanの後実行を防ぐ。DB transactionはOS APIを待つ間保持しない。OS effectsのawait中にDart timeoutだけでgateを解放しない（古い処理が遅れて実行され得る）。未知完了状態では正本・outboxを保ち、coordinatorの回復手順を実装前に証明する。期限だけのleaseにはOS側fencingがないため、それ単体を安全策としない。

native gateの同一process前提、複数engine登録、OSAPIへのchannel呼出しと終了時の責務は小さな技術spikeで確認が必要。別process writerを追加する場合は追加のOS同期排他が必要。永続化はSQLiteで別接続を保護するが、それだけでOS副作用を直列化できるとは主張しない。

権限拒否時もdomain操作は保存でき、予約は作らない。失敗の一般メッセージは次回foregroundで表示し、個人payloadをログへ出さない。lockscreen／iOSデータ保護で保存先を読めない場合は失敗として扱い、fallback保存やセキュリティ設定緩和をしない。既存の64件上限・未到達inexact予約保持を維持する。

## 匿名自動テスト案（未実施）

| 層 | 条件と期待結果 |
| --- | --- |
| parser/reducer | v2一致／null／未知version／不正action／ID再利用／同じ時刻で異なるgeneration。無効入力でwriteなし |
| idempotency | 同generationのあとで20連打でcount+1・1予定。同時刻を返すfake schedulerでも+1。同generationの完了とあとでの両順序で勝者1操作 |
| 別repository／別connection | barrierでforeground編集とbackground完了・あとで・新規保存・設定／timezone再計算を交差。全itemとmetadataを保持し、古いsnapshot上書きを拒否 |
| atomic/crash | commit前／途中／直後／OS成功後・ack前のfault injection。再openで全旧stateか全新state。consumeとcount/outboxに部分更新なし |
| migration | v0/v1、通知ID欠落・重複、破損・未知schema、並行初回import、commit中断。原文・savedAt・status・count・予約IDを保全。DB存在時に古いJSONへfallbackなし |
| effects race | fake OS callをbarrierで遅延し新revision保存と交差。gate越しに古いcancel/scheduleが後から適用されない。busy/timeout/失敗時outbox保持、再試行で重複countなし |
| UI routing | complete/snoozeはonOpen/URL/Navigator呼出し0。open/本文tapはUIへ1回・active維持。resumeでbackground結果を再読込 |
| native integration | Android/iOSの2engineで保存plugin・DB・process gateを確認。entry-point tree-shaking、registrant、Activityなし／lockscreen保存失敗を確認 |

fake/unit成功は実機成功と区別する。最後に専用試験itemでforeground/background/terminated、連打、再起動、権限拒否、lockscreen、音・振動・到達を本人操作で確認する。force-stop／OS制限下の動作は未保証として個別記録する。

## 実装順・レビュー条件

1. この設計と未知点を独立レビュー。次にtransaction repository contract・pure reducer・匿名fault testsを先行して作る（runtimeのbackground設定はまだ有効化しない）。
2. dependency／全writer移行／JSON保全・downgrade／native gateのspikeを別レビュー。ここが最大の変更範囲。
3. headless登録＋OS effectsを接続。CI OS buildとnative統合確認後、本人承認の専用APKで実機受入。
4. 実機未受入の間はDraft。通知previewの公開範囲は別の本人判断として変更しない。

## 権限・privacyと未確定点

設計上は新しいruntime permission、ネットワーク、認証、個人データ収集／送信を必要としない。merged manifest・依存SDKの挙動は実装時に再確認する。DBとJSONの重複保管・バックアップ適用範囲、iOS lockscreenのdata protection、background callback中のschedule/cancel完了可能性は未確定。既存と同じapp-private保存を維持し、protectionを弱めない。

## 独立設計レビュー結果・有効化を止める条件

2026-10-04 JST、現行コードと設計をread-onlyで独立レビューした。阻害点・安全な先行範囲は妥当だが、以下は背景処理を有効化する前の必須条件であり、解決済みとは扱わない。

1. **P1: 期限を過ぎたoutbox。** あとでのcommit後、OS予約前に終了し、復旧時には予定が過去だった場合を定義する。未実行effectsと、予約成功・配信済みを区別する。OSへの予約受付と実際の到達は同じackではない。遅配するか期限切れとして記録するかは未確定の製品ルールであり、未来のみ予約する現行syncでoutboxを黙って捨てない。実装前に方針を確定する。
2. **P1: 復元によるABA。** item incarnation＋保存系epochの要件を上記へ追加。backup復元・同ID再作成・generation巻戻り・OS側に残る旧通知を組み合わせたテストを追加する。復元検出・予約無効化を証明するまで導入しない。
3. **P1: native gateの回復契約。** gateはDart engineを所有者とせずnative coordinatorが所有する案とする。OS呼出し受理／完了／応答喪失の区別、engine破棄時もnative側の処理状態を保持する責務、process再起動後のpending照合とack、待機writerの復旧をspikeで確認する。安全な完了判定を作れなければwriterを永久待機させる構成を採用しない。タイムアウトだけの解放で古いOS処理を残す構成も採用しない。
4. **P2: 旧通知と遅配保持の移行。** 将来の旧予約はv2へ置換可能。予定を過ぎた未配信inexact予約は現行#32の保持条件を尊重し、無条件cancel／過去再登録をしない。表示済み旧通知のmutationボタンは拒否し、open/bodytapだけ読取扱い。OS APIだけでpending／displayed／不明を分類できない場合も未確定状態として保全し、過去予約を一律移行しない。移行方針と本人向け説明は実装前に確定する。

匿名テスト表へ追加する条件: commit→予約前停止→予定超過→再open、OS成功→ack前停止、engine破棄→native完了／応答喪失→待機writer復旧、old future／late pending／displayed／unknownの各移行、同ID再作成と復元epochの巻戻り。fake成功ではOS分類・回復を証明できないためnative統合と実機受入を分ける。

先行可能: runtime非接続のparser・pure reducer・transaction repository契約・匿名barrier／fault tests。永続化migrationやheadless action有効化は上記条件と依存レビューが終わるまで進めない。設計段階のテスト表は将来の検証計画であり、実施済み範囲は下記と区別する。

## 純粋領域の部分実装（2026-10-04 JST）

`lib/notifications/background_action.dart`にv2 payload parser、既存ScheduleEngine／InboxItemを利用するpure reducer、将来adapterのtransaction契約、3回までのCAS再読込serviceを追加した。既存通知payloadは引き続き旧形式であり、新コードの呼出し元・durable adapterはない。利用者の挙動は変更されない。`open`／本文tapは新serviceの対象外で、既存のUI起動経路を維持する。

`test/background_action_test.dart`は匿名in-memory fakeで、不正／旧payload、全token照合、同時刻の20連打、complete後duplicate、同snapshotの2writer、CAS競合時のmetadata／settings再読込、競合上限、commit前失敗と曖昧commit後の再受信を検証する。settings再読込は観測fake schedulerで渡された設定を直接確認する（初回snoozeの既存ルールはafterHomeMinuteを使わないため、予定差のassertにはしない）。11テスト成功、flutter analyze問題なし。独立レビューでコード本体に重大指摘なし。

fakeの同期CASとdirtyフラグは契約のテストであり、SQLite atomic outbox、実engine間排他、復元検出、OS通知回復の証明ではない。JSON保存の置換・SDK追加・manifest・headless登録・showsUserInterface設定は変更していない。Issue40を完了扱いにせず、上記の実装停止条件を保持する。

今回の指示はローカル純粋テストだけのため、追加OSビルドを起動せず、HEAD commitの`[skip ci]`で既存pull_request workflowを抑止する。CI成功とは報告しない。チェックはpendingとなり得るため、本Draftをそのままmergeできる状態とはしない。根拠: [GitHub workflow skip](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs)（同日確認）。

## 根拠（2026-10-04 JST確認）

- [flutter_local_notifications 22.3.1 Notification Actions](https://pub.dev/packages/flutter_local_notifications/versions/22.3.1#notification-actions): foregroundを外したactionは別engine/isolateから処理され、entry-pointとiOS registrantが必要。Android headless側にActivity contextはない。
- [SQLite isolation](https://www.sqlite.org/isolation.html)、[atomic commit](https://www.sqlite.org/atomiccommit.html): writerのtransaction直列化とcommit保証の根拠。OS予約とのatomic性までは保証しない。
- [Dart RandomAccessFile.lock](https://api.dart.dev/dart-io/RandomAccessFile/lock.html): OS X/Linuxのadvisory lockはprocess単位で、同processのisolate排他を証明しない。

設計段階では端末・APK・保存item・既存予約・権限を操作せず、新規Gradle cache／heavy buildも作らない。
