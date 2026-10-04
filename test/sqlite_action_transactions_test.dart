import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:atode_box/notifications/background_action.dart';
import 'package:atode_box/scheduling/schedule_engine.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/storage/sqlite_action_transactions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final at = DateTime.utc(2026, 10, 5, 10);
NotificationActionRecord fixture(String id, int nid) =>
    NotificationActionRecord(
      item: InboxItem(
        id: id,
        originalText: 'anonymous fixture',
        savedAt: at,
        nextNotifyAt: at,
        notificationId: nid,
        title: 'before',
      ),
      generation: 4,
      incarnation: 'fixture-$id',
      epoch: 'fixture-epoch',
    );
String payload() => jsonEncode({
  'v': 2,
  'id': 'a',
  'nid': 1,
  'at': at.toIso8601String(),
  'generation': 4,
  'incarnation': 'fixture-a',
  'epoch': 'fixture-epoch',
});

class SameTimeScheduler extends ScheduleEngine {
  @override
  Schedule snooze(InboxItem item, LifestyleSettings settings, DateTime now) =>
      Schedule(item.nextNotifyAt!, NotificationContext.nextWeek, 'fixture');
}

class ReadHook implements NotificationActionTransactions {
  ReadHook(this.delegate, this.hook);
  final SqliteActionTransactions delegate;
  final Future<void> Function() hook;
  int reads = 0;
  @override
  Future<NotificationActionSnapshot> read(String id) async {
    final result = await delegate.read(id);
    if (reads++ == 0) await hook();
    return result;
  }

  @override
  Future<bool> compareAndSwap({
    required int expectedRevision,
    required NotificationActionRecord previous,
    required NotificationActionRecord next,
  }) => delegate.compareAndSwap(
    expectedRevision: expectedRevision,
    previous: previous,
    next: next,
  );
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  late SqliteActionTransactions first;
  late SqliteActionTransactions second;
  Future<SqliteActionTransactions> open() =>
      SqliteActionTransactions.open(factory: databaseFactoryFfi, path: path);
  Future<BackgroundActionResult> act(
    NotificationActionTransactions adapter, {
    String action = 'snooze',
  }) => prepareBackgroundAction(
    transactions: adapter,
    actionId: action,
    payload: payload(),
    now: at,
    scheduler: SameTimeScheduler(),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atode-anonymous-db-');
    path = '${directory.path}${Platform.pathSeparator}actions.db';
    first = await open();
    await first.seedPrototype(records: [fixture('a', 1), fixture('b', 2)]);
    second = await open();
    expect(identical(first.database, second.database), isFalse);
  });
  tearDown(() async {
    await first.close();
    await second.close();
    // Only the exact anonymous temporary directory created by this test.
    await directory.delete(recursive: true);
  });

  test(
    'duplicate delivery on separate connections consumes once, same time',
    () async {
      final results = await Future.wait(
        List.generate(20, (i) => act(i.isEven ? first : second)),
      );
      expect(
        results.where((r) => r == BackgroundActionResult.applied).length,
        1,
      );
      expect(
        results.where((r) => r == BackgroundActionResult.ignored).length,
        19,
      );
      final result = await second.read('a');
      expect(result.revision, 1);
      expect(result.record!.generation, 5);
      expect(result.record!.item.snoozeCount, 1);
      expect(result.record!.item.nextNotifyAt, at);
      expect(
        (await second.read('b')).record!.item.toJson(),
        fixture('b', 2).item.toJson(),
      );
      expect(await first.pendingEffectsRevision(), 1);
    },
  );

  test(
    'barrier complete versus snooze uses the same committed snapshot',
    () async {
      final ready = Completer<void>();
      var readers = 0;
      Future<void> barrier() async {
        if (++readers == 2) ready.complete();
        await ready.future;
      }

      final results = await Future.wait([
        act(ReadHook(first, barrier), action: 'complete'),
        act(ReadHook(second, barrier)),
      ]);
      expect(
        results.where((r) => r == BackgroundActionResult.applied).length,
        1,
      );
      expect(
        results.where((r) => r == BackgroundActionResult.ignored).length,
        1,
      );
      expect((await first.read('a')).revision, 1);
      expect((await first.read('a')).record!.generation, 5);
    },
  );

  test(
    'CAS retry retains concurrent title/settings and the other item',
    () async {
      final hooked = ReadHook(first, () async {
        await second.editTitleForPrototype('a', 'concurrent title');
        await second.saveSettingsForPrototype(
          const LifestyleSettings(afterHomeMinute: 20 * 60),
        );
      });
      expect(await act(hooked), BackgroundActionResult.applied);
      expect(hooked.reads, 2);
      final result = await second.read('a');
      expect(result.revision, 3);
      expect(result.record!.item.title, 'concurrent title');
      expect(result.settings.afterHomeMinute, 20 * 60);
      expect((await second.read('b')).record!.generation, 4);
    },
  );

  test(
    'outbox failure rolls back item, generation and document revision',
    () async {
      await first.database.execute('''
      CREATE TRIGGER fail_outbox BEFORE INSERT ON action_outbox
      BEGIN SELECT RAISE(ABORT, 'anonymous fault'); END
    ''');
      await expectLater(act(first), throwsA(isA<DatabaseException>()));
      final result = await second.read('a');
      expect(result.revision, 0);
      expect(result.record!.generation, 4);
      expect(result.record!.item.snoozeCount, 0);
      expect(await second.pendingEffectsRevision(), isNull);
      await first.database.execute('DROP TRIGGER fail_outbox');
      expect(await act(first), BackgroundActionResult.applied);
    },
  );

  test(
    'commit survives close/reopen and stale ack cannot clear newer work',
    () async {
      expect(await act(first), BackgroundActionResult.applied);
      await first.close();
      first = await open();
      expect((await first.read('a')).record!.generation, 5);
      expect(await first.pendingEffectsRevision(), 1);
      expect(await act(first), BackgroundActionResult.ignored);
      await second.editTitleForPrototype('b', 'newer effect');
      expect(await first.acknowledgeEffects(1), isFalse);
      expect(await first.pendingEffectsRevision(), 2);
      expect(await first.acknowledgeEffects(2), isTrue);
      expect(await first.pendingEffectsRevision(), isNull);
    },
  );

  test('seed is once-only and corrupt schema is not rewritten', () async {
    expect(await second.seedPrototype(records: [fixture('a', 1)]), isFalse);
    expect((await first.read('b')).record, isNotNull);
    await first.database.update('action_document', {
      'contents': '{"schema_version":99}',
    });
    await expectLater(act(second), throwsStateError);
    final row = (await first.database.query('action_document')).single;
    expect(row['contents'], '{"schema_version":99}');
    expect(row['revision'], 0);
    expect(await first.pendingEffectsRevision(), isNull);
  });

  test(
    'same revision but mismatched previous token performs no writes',
    () async {
      final snapshot = await first.read('a');
      final next = reduceBackgroundAction(
        snapshot: snapshot,
        token: NotificationActionToken.parse(payload())!,
        action: BackgroundAction.complete,
        scheduler: const ScheduleEngine(),
        now: at,
      )!;
      final wrong = NotificationActionRecord(
        item: snapshot.record!.item,
        generation: 3,
        incarnation: 'fixture-a',
        epoch: 'fixture-epoch',
      );
      expect(
        await second.compareAndSwap(
          expectedRevision: 0,
          previous: wrong,
          next: next,
        ),
        isFalse,
      );
      expect((await first.read('a')).revision, 0);
      expect(await first.pendingEffectsRevision(), isNull);
    },
  );

  test(
    'held writer lock fails boundedly before mutation then can retry',
    () async {
      final locked = Completer<void>();
      final release = Completer<void>();
      final holder = second.database.transaction((txn) async {
        locked.complete();
        await release.future;
      }, exclusive: false);
      await locked.future;
      try {
        await expectLater(act(first), throwsA(isA<DatabaseException>()));
        expect((await first.read('a')).revision, 0);
        expect(await first.pendingEffectsRevision(), isNull);
      } finally {
        release.complete();
        await holder;
      }
      expect(await act(first), BackgroundActionResult.applied);
    },
  );

  test(
    'maximum actionable generation consumes to a non-actionable terminal',
    () async {
      final rows = await first.database.query('action_document');
      final document =
          jsonDecode(rows.single['contents'] as String) as Map<String, dynamic>;
      (document['records'] as List<dynamic>).first['generation'] =
          9007199254740990;
      await first.database.update('action_document', {
        'contents': jsonEncode(document),
      });
      final token = jsonDecode(payload()) as Map<String, dynamic>;
      token['generation'] = 9007199254740990;
      expect(
        await prepareBackgroundAction(
          transactions: first,
          actionId: 'complete',
          payload: jsonEncode(token),
          now: at,
        ),
        BackgroundActionResult.applied,
      );
      expect((await second.read('a')).record!.generation, 9007199254740991);
      token['generation'] = 9007199254740991;
      expect(NotificationActionToken.parse(jsonEncode(token)), isNull);
      expect((await second.read('a')).revision, 1);
    },
  );

  test(
    'corrupt duplicate notification identity is rejected without overwrite',
    () async {
      final rows = await first.database.query('action_document');
      final document =
          jsonDecode(rows.single['contents'] as String) as Map<String, dynamic>;
      (document['records'] as List<dynamic>)[1]['item']['notification_id'] = 1;
      final corrupted = jsonEncode(document);
      await first.database.update('action_document', {'contents': corrupted});
      await expectLater(act(second), throwsStateError);
      expect(
        (await first.database.query('action_document')).single['contents'],
        corrupted,
      );
      expect(await first.pendingEffectsRevision(), isNull);
    },
  );
}
