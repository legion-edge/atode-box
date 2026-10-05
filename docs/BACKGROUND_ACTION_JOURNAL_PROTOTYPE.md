# PR A extracted validation boundary

Current A: analysis and all151 tests passed. Counts117/154 below describe earlier prototype snapshots on the original working branch; they are not this extracted branch's suite total. Native admission/runtime and later Android acceptance are outside A. See [A contract](SHARED_ACTION_STORAGE_CONTRACT.md).

# 背景action journalのローカル試作

[Aの共有契約と未実証境界](SHARED_ACTION_STORAGE_CONTRACT.md)を参照する。以下はWindows FFI adapterの検証範囲であり、native接続と実機受入はこの抽出ブランチに含まない。

Issue #40向けの実験用SQLite adapterにdurableな受付journalを追加した。productionのLocalRepository、native receiver、端末の通知には接続していない。匿名fixtureのWindows SQLite FFI試験であり、Android/iOSの背景実行や通知到達を証明する結果ではない。

## 受付と処理の契約

`receiveActionForPrototype`は厳密なv2 token、complete/snooze、最新canonicalのactive状態と全tokenフィールドを確認してreceiptを保存する。JSONのkey順や空白は正規化する。同じaction＋tokenだけを重複排除し、受付時にはitem、revision、outboxを変更しない。完了とあとでは両方受付可能で、先にdomainをcommitした操作がgenerationを消費する。

`drainActionForPrototype`はpendingをsequence順のFIFOで処理し、最新itemとsettingsで再検証・計算する。この試作では通常は先受付のpendingからcommitする。domain変更、revision増加、outbox、receipt完了を一つのtransactionでcommitする。古いgenerationはignoredとして保全する。不正receiptはcanonicalの検証後にblockedへ隔離し、内容を残して正常な後続処理を可能にする。blockedを含む保管期間、foreground診断、再処理手順はproduction接続時に設計する。現時点ではreceiptを削除しない。

実験用schema v1からv2へのupgradeはjournal追加のみで、canonical/outboxを保存する。production JSONのimportやrestore migrationではない。試作中の旧v2定義で作成したDBは対応しない。今回のDBは各テストで新規作成し終了時に破棄する匿名fixtureのみである。

## 確認した範囲

新規9テストは、受付後のclose/reopen、commit後の再配信、2接続から20重複受付・処理、完了とあとでの競合、receipt完了失敗時のdomain/outbox rollback、受付後のtitle/settings変更、古いreceiptの退役、不正payloadとJSON正規化、実験用v1 upgrade、不正receiptの隔離を確認した。全154テストと`flutter analyze`が成功した。独立read-onlyレビューで重大な懸念はなかった。

## 未実証の境界

native callbackはDart起動、OS通知cancel、callback acknowledgmentより前にjournalへ保存する必要がある。この試作はDartのFFI APIで受付しており、そのnative admission順序を実装・実証していない。実際のengine破棄、native OS coordinator、OS受付後ack前の中断、boot/receiver writerの統合、restore epoch、全production writerの移行も未完了。outboxの存在は通知配信の証拠ではない。

[最小native spikeの計画](SHARED_ACTION_STORAGE_CONTRACT.md)に沿って、専用匿名データと通知namespaceで上記境界を先に実証する。現在はOS build、実機操作、remote pushを保留している。
