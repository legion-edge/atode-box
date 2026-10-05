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
        originalText: 'anonymous journal fixture',
        savedAt: at,
        notificationId: nid,
        nextNotifyAt: at,
        title: 'before',
      ),
      generation: 4,
      incarnation: 'fixture-$id',
      epoch: 'fixture-install',
    );
String payload([Map<String, Object?> changes = const {}]) => jsonEncode({
  'v': 2,
  'id': 'a',
  'nid': 1,
  'at': at.toIso8601String(),
  'generation': 4,
  'incarnation': 'fixture-a',
  'epoch': 'fixture-install',
  ...changes,
});

class ObservingScheduler extends ScheduleEngine {
  LifestyleSettings? observed;
  @override
  Schedule snooze(InboxItem item, LifestyleSettings settings, DateTime now) {
    observed = settings;
    return Schedule(
      item.nextNotifyAt!,
      NotificationContext.nextWeek,
      'fixture',
    );
  }
}

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  late SqliteActionTransactions first;
  late SqliteActionTransactions second;
  Future<SqliteActionTransactions> open() =>
      SqliteActionTransactions.open(factory: databaseFactoryFfi, path: path);
  Future<PrototypeActionReception> receive(
    SqliteActionTransactions adapter, {
    String action = 'snooze',
    String? value,
  }) => adapter.receiveActionForPrototype(
    actionId: action,
    payload: value ?? payload(),
  );
  Future<PrototypeActionDrain> drain(SqliteActionTransactions adapter) =>
      adapter.drainActionForPrototype(now: at, scheduler: ObservingScheduler());

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('atode-action-journal-');
    path = '${directory.path}${Platform.pathSeparator}actions.db';
    first = await open();
    await first.seedPrototype(records: [fixture('a', 1), fixture('b', 2)]);
    second = await open();
  });
  tearDown(() async {
    await first.close();
    await second.close();
    await directory.delete(recursive: true);
  });

  test('receipt survives reopen before worker and redelivery is not a second action', () async {
    expect(await receive(first), PrototypeActionReception.accepted);
    expect((await first.read('a')).record!.item.snoozeCount, 0);
    expect(await first.pendingEffectsRevision(), isNull);
    await first.close();
    first = await open();
    expect(await receive(first), PrototypeActionReception.duplicate);
    expect(await drain(second), PrototypeActionDrain.applied);
    await second.close();
    second = await open();
    expect(await drain(second), PrototypeActionDrain.empty);
    expect((await first.read('a')).record!.item.snoozeCount, 1);
    expect((await first.read('a')).record!.generation, 5);
    expect(await first.pendingEffectsRevision(), 1);
    expect(
      (await first.database.query('action_journal')).single['state'],
      'applied',
    );
  });

  test(
    'separate connection duplicate reception and parallel drain consume once',
    () async {
      final receptions = await Future.wait(
        List.generate(20, (i) => receive(i.isEven ? first : second)),
      );
      expect(
        receptions.where((r) => r == PrototypeActionReception.accepted).length,
        1,
      );
      expect(
        receptions.where((r) => r == PrototypeActionReception.duplicate).length,
        19,
      );
      final drains = await Future.wait(
        List.generate(20, (i) => drain(i.isEven ? first : second)),
      );
      expect(drains.where((r) => r == PrototypeActionDrain.applied).length, 1);
      expect(drains.where((r) => r == PrototypeActionDrain.empty).length, 19);
      expect((await first.read('a')).revision, 1);
    },
  );

  test(
    'first domain commit consumes the other accepted action for one generation',
    () async {
      expect(
        await receive(first, action: 'complete'),
        PrototypeActionReception.accepted,
      );
      expect(await receive(second), PrototypeActionReception.accepted);
      expect(await drain(first), PrototypeActionDrain.applied);
      expect(
        (await second.read('a')).record!.item.status,
        ItemStatus.completed,
      );
      expect((await second.read('a')).record!.item.snoozeCount, 0);
      expect(await drain(second), PrototypeActionDrain.ignored);
      expect((await second.read('a')).revision, 1);
    },
  );

  test('receipt completion failure rolls back domain/outbox and leaves work pending', () async {
    await receive(first);
    await first.database.execute('''
      CREATE TRIGGER fail_receipt BEFORE UPDATE OF state ON action_journal
      BEGIN SELECT RAISE(ABORT, 'anonymous receipt fault'); END
    ''');
    await expectLater(drain(second), throwsA(isA<DatabaseException>()));
    expect((await first.read('a')).revision, 0);
    expect((await first.read('a')).record!.generation, 4);
    expect((await first.read('a')).record!.item.snoozeCount, 0);
    expect(await first.pendingEffectsRevision(), isNull);
    expect(
      (await first.database.query('action_journal')).single['state'],
      'pending',
    );
    await first.database.execute('DROP TRIGGER fail_receipt');
    expect(await drain(second), PrototypeActionDrain.applied);
    expect((await first.read('a')).record!.item.snoozeCount, 1);
  });

  test(
    'worker loads current metadata/settings and preserves the other item',
    () async {
      await receive(first);
      await second.editTitleForPrototype('a', 'concurrent title');
      await second.saveSettingsForPrototype(
        const LifestyleSettings(
          afterHomeMinute: 20 * 60,
          overdueRecoveryPolicy: OverdueRecoveryPolicy.notifyOnRecovery,
        ),
      );
      final scheduler = ObservingScheduler();
      expect(
        await first.drainActionForPrototype(now: at, scheduler: scheduler),
        PrototypeActionDrain.applied,
      );
      expect(scheduler.observed!.afterHomeMinute, 20 * 60);
      expect(
        scheduler.observed!.overdueRecoveryPolicy,
        OverdueRecoveryPolicy.notifyOnRecovery,
      );
      expect((await first.read('a')).record!.item.title, 'concurrent title');
      expect((await first.read('a')).revision, 3);
      expect(
        (await first.read('b')).record!.item.toJson(),
        fixture('b', 2).item.toJson(),
      );
    },
  );

  test(
    'superseded receipt is retired without reapplying to a newer generation',
    () async {
      await receive(first);
      expect(
        await prepareBackgroundAction(
          transactions: second,
          actionId: 'complete',
          payload: payload(),
          now: at,
        ),
        BackgroundActionResult.applied,
      );
      expect(await drain(first), PrototypeActionDrain.ignored);
      expect((await first.read('a')).revision, 1);
      expect((await first.read('a')).record!.item.status, ItemStatus.completed);
      expect(
        (await first.database.query('action_journal')).single['state'],
        'ignored',
      );
      expect(await first.pendingEffectsRevision(), 1);
    },
  );

  test('semantic JSON duplicates normalize and invalid actions/tokens never enqueue', () async {
    for (final value in [
      'a|legacy',
      payload({'v': 3}),
      payload({'generation': 3}),
      payload({'epoch': 'other'}),
    ]) {
      expect(
        await receive(first, value: value),
        PrototypeActionReception.ignored,
      );
    }
    expect(
      await receive(first, action: 'open'),
      PrototypeActionReception.ignored,
    );
    expect(await first.database.query('action_journal'), isEmpty);
    await receive(first);
    final map = jsonDecode(payload()) as Map<String, dynamic>;
    final reordered = {
      for (final key in map.keys.toList().reversed) key: map[key],
    };
    expect(
      await receive(
        second,
        value: const JsonEncoder.withIndent(' ').convert(reordered),
      ),
      PrototypeActionReception.duplicate,
    );
    expect((await first.database.query('action_journal')).length, 1);
    expect((await first.read('a')).revision, 0);
  });

  test(
    'experimental v1 upgrade adds only journal and preserves canonical/outbox',
    () async {
      final document = (await first.database.query('action_document')).single;
      final legacyPath = '${directory.path}${Platform.pathSeparator}v1.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute(
              'CREATE TABLE action_document (id INTEGER PRIMARY KEY, revision INTEGER, contents TEXT)',
            );
            await db.execute(
              'CREATE TABLE action_outbox (id INTEGER PRIMARY KEY, revision INTEGER)',
            );
          },
        ),
      );
      await legacy.insert('action_document', document);
      await legacy.insert('action_outbox', {'id': 1, 'revision': 0});
      await legacy.close();
      final upgraded = await SqliteActionTransactions.open(
        factory: databaseFactoryFfi,
        path: legacyPath,
      );
      try {
        expect(
          (await upgraded.database.query('action_document')).single,
          document,
        );
        expect(await upgraded.pendingEffectsRevision(), 0);
        expect(await upgraded.database.query('action_journal'), isEmpty);
        expect(await receive(upgraded), PrototypeActionReception.accepted);
        expect(await drain(upgraded), PrototypeActionDrain.applied);
      } finally {
        await upgraded.close();
      }
    },
  );

  test(
    'corrupt receipt is preserved and blocked while later work can proceed',
    () async {
      await receive(first);
      await receive(
        second,
        value: payload({'id': 'b', 'nid': 2, 'incarnation': 'fixture-b'}),
      );
      await first.database.update(
        'action_journal',
        {'token': '{}'},
        where: 'sequence = ?',
        whereArgs: [1],
      );
      expect(await drain(second), PrototypeActionDrain.blocked);
      expect((await first.read('a')).revision, 0);
      expect(await first.pendingEffectsRevision(), isNull);
      final quarantined = (await first.database.query(
        'action_journal',
        where: 'sequence = ?',
        whereArgs: [1],
      )).single;
      expect(quarantined['token'], '{}');
      expect(quarantined['state'], 'blocked');
      expect(await drain(first), PrototypeActionDrain.applied);
      expect((await first.read('b')).record!.item.snoozeCount, 1);
      expect((await first.read('a')).record!.item.snoozeCount, 0);
      expect(await drain(first), PrototypeActionDrain.empty);
    },
  );
}
