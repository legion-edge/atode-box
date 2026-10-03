import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:atode_box/notifications/background_action.dart';
import 'package:atode_box/scheduling/schedule_engine.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/lifestyle_settings.dart';

final instant = DateTime.utc(2026, 10, 5, 10);

NotificationActionRecord fixture({String id = 'fixture-a'}) =>
    NotificationActionRecord(
      item: InboxItem(
        id: id,
        originalText: '匿名の試験項目',
        savedAt: instant.subtract(const Duration(days: 1)),
        nextNotifyAt: instant,
        notificationId: id == 'fixture-a' ? 1 : 2,
        title: '試験タイトル',
        url: 'https://example.com',
      ),
      generation: 4,
      incarnation: 'incarnation-a',
      epoch: 'installation-a',
    );

String payload([Map<String, Object?> changes = const {}]) => jsonEncode({
  'v': 2,
  'id': 'fixture-a',
  'nid': 1,
  'at': instant.toIso8601String(),
  'generation': 4,
  'incarnation': 'incarnation-a',
  'epoch': 'installation-a',
  ...changes,
});

class SameTimeScheduler extends ScheduleEngine {
  const SameTimeScheduler();

  @override
  Schedule snooze(InboxItem item, LifestyleSettings settings, DateTime now) =>
      Schedule(item.nextNotifyAt!, NotificationContext.nextWeek, 'fixture');
}

class SettingsObservingScheduler extends SameTimeScheduler {
  final observed = <LifestyleSettings>[];

  @override
  Schedule snooze(InboxItem item, LifestyleSettings settings, DateTime now) {
    observed.add(settings);
    return super.snooze(item, settings, now);
  }
}

/// Contract fake only: no filesystem, SQLite, native engine or OS effects.
class MemoryTransactions implements NotificationActionTransactions {
  final records = {
    'fixture-a': fixture(),
    'fixture-b': fixture(id: 'fixture-b'),
  };
  LifestyleSettings settings = const LifestyleSettings();
  int revision = 0;
  int reads = 0;
  int attempts = 0;
  int commits = 0;
  bool dirty = false;
  bool refuse = false;
  bool throwBefore = false;
  bool throwAfter = false;
  Future<void> Function()? afterRead;
  void Function()? beforeCas;

  @override
  Future<NotificationActionSnapshot> read(String itemId) async {
    reads++;
    final result = NotificationActionSnapshot(
      revision: revision,
      record: records[itemId],
      settings: settings,
    );
    await afterRead?.call();
    return result;
  }

  @override
  Future<bool> compareAndSwap({
    required int expectedRevision,
    required NotificationActionRecord previous,
    required NotificationActionRecord next,
  }) async {
    attempts++;
    final hook = beforeCas;
    beforeCas = null;
    hook?.call();
    if (throwBefore) throw StateError('fixture before commit');
    final current = records[previous.item.id];
    if (refuse ||
        revision != expectedRevision ||
        current?.generation != previous.generation ||
        current?.incarnation != previous.incarnation ||
        current?.epoch != previous.epoch) {
      return false;
    }
    records[next.item.id] = next;
    revision++;
    dirty = true;
    commits++;
    if (throwAfter) throw StateError('fixture ambiguous commit');
    return true;
  }
}

Future<BackgroundActionResult> run(
  MemoryTransactions store, {
  String action = 'snooze',
  String? notice,
}) => prepareBackgroundAction(
  transactions: store,
  actionId: action,
  payload: notice ?? payload(),
  now: instant,
  scheduler: const SameTimeScheduler(),
);

void main() {
  test('strict v2 parser rejects legacy and malformed payloads', () {
    expect(NotificationActionToken.parse(payload()), isNotNull);
    for (final value in [
      null,
      '',
      'fixture-a|${instant.toIso8601String()}',
      '[]',
      '{',
      payload({'v': 3}),
      payload({'v': 2.0}),
      payload({'id': ''}),
      payload({'nid': 0}),
      payload({'nid': 2147483648}),
      payload({'generation': -1}),
      payload({'generation': 4.0}),
      payload({'generation': 9007199254740991}),
      payload({'incarnation': ''}),
      payload({'epoch': null}),
      payload({'at': '2026-10-05T10:00:00+00:00'}),
      payload({'at': '2026-02-30T10:00:00.000Z'}),
      payload({'extra': 'unexpected'}),
      'x' * 2049,
    ]) {
      expect(NotificationActionToken.parse(value), isNull, reason: '$value');
    }
  });

  test('invalid action or old payload makes no repository calls', () async {
    final store = MemoryTransactions();
    expect(await run(store, action: 'open'), BackgroundActionResult.ignored);
    expect(await run(store, action: ''), BackgroundActionResult.ignored);
    expect(
      await run(store, notice: 'fixture-a|old'),
      BackgroundActionResult.ignored,
    );
    expect(store.reads, 0);
    expect(store.attempts, 0);
  });

  test('all token dimensions must match fresh active record', () async {
    for (final change in [
      {'id': 'missing'},
      {'nid': 2},
      {'at': instant.add(const Duration(seconds: 1)).toIso8601String()},
      {'generation': 3},
      {'incarnation': 'recreated-item'},
      {'epoch': 'restored-installation'},
    ]) {
      final store = MemoryTransactions();
      expect(
        await run(store, notice: payload(change)),
        BackgroundActionResult.ignored,
      );
      expect(store.commits, 0);
      expect(store.dirty, isFalse);
    }
    for (final status in [ItemStatus.completed, ItemStatus.deleted]) {
      final store = MemoryTransactions();
      final old = store.records['fixture-a']!;
      store.records['fixture-a'] = NotificationActionRecord(
        item: old.item.copyWith(status: status),
        generation: old.generation,
        incarnation: old.incarnation,
        epoch: old.epoch,
      );
      expect(await run(store), BackgroundActionResult.ignored);
      expect(store.commits, 0);
    }
  });

  test(
    '20 duplicate snoozes consume generation once even at same time',
    () async {
      final store = MemoryTransactions();
      for (var i = 0; i < 20; i++) {
        expect(
          await run(store),
          i == 0
              ? BackgroundActionResult.applied
              : BackgroundActionResult.ignored,
        );
      }
      final result = store.records['fixture-a']!;
      expect(result.item.snoozeCount, 1);
      expect(result.item.nextNotifyAt, instant);
      expect(result.generation, 5);
      expect(result.item.originalText, fixture().item.originalText);
      expect(result.item.savedAt, fixture().item.savedAt);
      expect(store.commits, 1);
      expect(store.dirty, isTrue);
    },
  );

  test(
    'complete consumes duplicate complete and snooze without reopening',
    () async {
      final store = MemoryTransactions();
      expect(
        await run(store, action: 'complete'),
        BackgroundActionResult.applied,
      );
      expect(
        await run(store, action: 'complete'),
        BackgroundActionResult.ignored,
      );
      expect(await run(store), BackgroundActionResult.ignored);
      expect(store.records['fixture-a']!.item.status, ItemStatus.completed);
      expect(store.records['fixture-a']!.item.snoozeCount, 0);
      expect(store.commits, 1);
    },
  );

  for (final actions in [
    ['snooze', 'snooze'],
    ['complete', 'snooze'],
    ['snooze', 'complete'],
  ]) {
    test('two writers with same snapshot: $actions have one winner', () async {
      final store = MemoryTransactions();
      final barrier = Completer<void>();
      var readers = 0;
      store.afterRead = () async {
        if (++readers == 2) barrier.complete();
        await barrier.future;
      };
      final results = await Future.wait(
        actions.map((action) => run(store, action: action)),
      );
      expect(
        results
            .where((value) => value == BackgroundActionResult.applied)
            .length,
        1,
      );
      expect(
        results
            .where((value) => value == BackgroundActionResult.ignored)
            .length,
        1,
      );
      expect(store.commits, 1);
      expect(store.records['fixture-a']!.generation, 5);
      expect(
        store.records['fixture-a']!.item.snoozeCount,
        lessThanOrEqualTo(1),
      );
    });
  }

  test(
    'CAS conflict reloads metadata and settings without losing other item',
    () async {
      final store = MemoryTransactions();
      final other = store.records['fixture-b'];
      store.beforeCas = () {
        final old = store.records['fixture-a']!;
        store.records['fixture-a'] = NotificationActionRecord(
          item: old.item.copyWith(title: '更新済み匿名タイトル'),
          generation: old.generation,
          incarnation: old.incarnation,
          epoch: old.epoch,
        );
        store.settings = const LifestyleSettings(afterHomeMinute: 20 * 60);
        store.revision++;
      };
      final scheduler = SettingsObservingScheduler();
      expect(
        await prepareBackgroundAction(
          transactions: store,
          actionId: 'snooze',
          payload: payload(),
          now: instant,
          scheduler: scheduler,
        ),
        BackgroundActionResult.applied,
      );
      expect(scheduler.observed.map((value) => value.afterHomeMinute), [
        19 * 60,
        20 * 60,
      ]);
      expect(store.attempts, 2);
      expect(store.reads, 2);
      expect(store.records['fixture-a']!.item.title, '更新済み匿名タイトル');
      expect(store.records['fixture-b'], same(other));
      expect(store.settings.afterHomeMinute, 20 * 60);
      expect(store.commits, 1);
    },
  );

  test('conflicts have bounded retries and no mutation', () async {
    final store = MemoryTransactions()..refuse = true;
    expect(await run(store), BackgroundActionResult.conflict);
    expect(store.attempts, 3);
    expect(store.commits, 0);
    expect(store.records['fixture-a']!.item.snoozeCount, 0);
  });

  test(
    'failed and ambiguous commits propagate; redelivery never doubles count',
    () async {
      final before = MemoryTransactions()..throwBefore = true;
      await expectLater(run(before), throwsStateError);
      expect(before.attempts, 1);
      expect(before.commits, 0);
      before.throwBefore = false;
      expect(await run(before), BackgroundActionResult.applied);

      final after = MemoryTransactions()..throwAfter = true;
      await expectLater(run(after), throwsStateError);
      expect(after.attempts, 1);
      expect(after.commits, 1);
      after.throwAfter = false;
      expect(await run(after), BackgroundActionResult.ignored);
      expect(after.records['fixture-a']!.item.snoozeCount, 1);
      expect(after.commits, 1);
    },
  );
}
