import 'dart:convert';
import 'dart:io';

import 'package:atode_box/notifications/background_action.dart';
import 'package:atode_box/notifications/overdue_recovery.dart';
import 'package:atode_box/scheduling/schedule_engine.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 10, 4, 13);
final missedAt = now.subtract(const Duration(hours: 1));
const scheduler = ScheduleEngine(zone: FixedOffsetZone(Duration(hours: 9)));

NotificationActionRecord record({
  int count = 0,
  ItemStatus status = ItemStatus.active,
}) => NotificationActionRecord(
  item: InboxItem(
    id: 'anonymous',
    originalText: 'anonymous fixture',
    savedAt: now.subtract(const Duration(days: 1)),
    title: 'fixture title',
    url: 'https://example.com',
    category: ItemCategory.memo,
    status: status,
    snoozeCount: count,
    notificationId: 1,
    nextNotifyAt: missedAt,
  ),
  generation: 4,
  incarnation: 'fixture-item',
  epoch: 'fixture-install',
);

NotificationActionToken token([Map<String, Object?> changes = const {}]) =>
    NotificationActionToken.parse(
      jsonEncode({
        'v': 2,
        'id': 'anonymous',
        'nid': 1,
        'at': missedAt.toIso8601String(),
        'generation': 4,
        'incarnation': 'fixture-item',
        'epoch': 'fixture-install',
        ...changes,
      }),
    )!;

class MemoryStore implements DocumentStore {
  String? contents;
  @override
  Future<String?> read() async => contents;
  @override
  Future<void> write(String value) async => contents = value;
}

class UnexpectedRecalculation extends ScheduleEngine {
  @override
  Schedule recalculate(
    InboxItem item,
    LifestyleSettings settings,
    DateTime now,
  ) => throw StateError('Policy-only edit must preserve existing reservations');
}

void main() {
  for (final policy in OverdueRecoveryPolicy.values) {
    for (final count in [0, 1, 3]) {
      test(
        'confirmed overdue recovery $policy preserves snooze stage $count',
        () {
          final previous = record(count: count);
          final settings = LifestyleSettings(overdueRecoveryPolicy: policy);
          final result = recoverConfirmedOverdueNotice(
            record: previous,
            token: token(),
            nonDeliveryConfirmed: true,
            settings: settings,
            now: now,
            scheduler: scheduler,
          )!;
          final item = result.next.item;
          expect(item.snoozeCount, count);
          expect(item.originalText, previous.item.originalText);
          expect(item.savedAt, previous.item.savedAt);
          expect(item.title, previous.item.title);
          expect(item.url, previous.item.url);
          expect(item.notificationId, 1);
          expect(item.status, ItemStatus.active);
          expect(result.next.generation, 5);
          expect(result.next.epoch, previous.epoch);
          expect(result.next.incarnation, previous.incarnation);
          if (policy == OverdueRecoveryPolicy.nextRegularSlot) {
            final schedule = scheduler.recalculate(
              previous.item,
              settings,
              now,
            );
            expect(item.nextNotifyAt, schedule.at);
            expect(item.nextNotifyAt!.isAfter(now), isTrue);
            expect(item.context, schedule.context.storageKey);
            expect(result.delivery, RecoveredNoticeDelivery.scheduleFuture);
          } else {
            expect(item.nextNotifyAt, now);
            expect(item.context, isNull);
            expect(result.delivery, RecoveredNoticeDelivery.notifyOnRecovery);
          }
          expect(
            recoverConfirmedOverdueNotice(
              record: result.next,
              token: token(),
              nonDeliveryConfirmed: true,
              settings: settings,
              now: now.add(const Duration(days: 10)),
              scheduler: scheduler,
            ),
            isNull,
          );
        },
      );
    }
  }

  test('absence without proof cannot trigger either recovery policy', () {
    for (final policy in OverdueRecoveryPolicy.values) {
      expect(
        recoverConfirmedOverdueNotice(
          record: record(),
          token: token(),
          nonDeliveryConfirmed: false,
          settings: LifestyleSettings(overdueRecoveryPolicy: policy),
          now: now,
        ),
        isNull,
      );
    }
  });

  test('proof is bound to active exact token and a strictly overdue time', () {
    for (final changes in <Map<String, Object?>>[
      {'id': 'other'},
      {'nid': 2},
      {'generation': 3},
      {'incarnation': 'other'},
      {'epoch': 'other'},
      {'at': now.toIso8601String()},
    ]) {
      expect(
        recoverConfirmedOverdueNotice(
          record: record(),
          token: token(changes),
          nonDeliveryConfirmed: true,
          settings: const LifestyleSettings(),
          now: now,
        ),
        isNull,
      );
    }
    for (final status in [ItemStatus.completed, ItemStatus.deleted]) {
      expect(
        recoverConfirmedOverdueNotice(
          record: record(status: status),
          token: token(),
          nonDeliveryConfirmed: true,
          settings: const LifestyleSettings(),
          now: now,
        ),
        isNull,
      );
    }
    for (final instant in [
      missedAt,
      missedAt.subtract(const Duration(seconds: 1)),
    ]) {
      expect(
        recoverConfirmedOverdueNotice(
          record: record(),
          token: token(),
          nonDeliveryConfirmed: true,
          settings: const LifestyleSettings(),
          now: instant,
        ),
        isNull,
      );
    }
  });

  test('v0/v1 settings missing policy default to next regular slot', () async {
    for (final version in [0, 1]) {
      final store = MemoryStore()
        ..contents = jsonEncode({
          if (version != 0) 'schema_version': version,
          'items': [],
          'settings': {'commute_start_minute': 17 * 60},
        });
      final settings = await LocalRepository(store).getSettings();
      expect(
        settings.overdueRecoveryPolicy,
        OverdueRecoveryPolicy.nextRegularSlot,
      );
      expect(settings.commuteStartMinute, 17 * 60);
    }
    expect(
      () => LifestyleSettings.fromJson({'overdue_recovery_policy': 'unknown'}),
      throwsFormatException,
    );
  });

  test('both settings persist across file repository reopen, policy-only save preserves items', () async {
    final directory = await Directory.systemTemp.createTemp(
      'atode-recovery-policy-',
    );
    try {
      final repository = LocalRepository(FileDocumentStore(directory));
      await repository.saveItem(record(count: 3).item);
      final before = (await repository.allItems()).single.toJson();
      for (final policy in OverdueRecoveryPolicy.values.reversed) {
        final settings = (await repository.getSettings()).copyWith(
          overdueRecoveryPolicy: policy,
        );
        final change = await repository.saveSettingsWithSchedules(
          settings,
          UnexpectedRecalculation(),
          now,
        );
        expect(change.scheduleChanged, isFalse);
        final reopened = LocalRepository(FileDocumentStore(directory));
        expect((await reopened.getSettings()).overdueRecoveryPolicy, policy);
        expect((await reopened.allItems()).single.toJson(), before);
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'unknown policy never publishes a partial cache or overwrites the file',
    () async {
      final source = jsonEncode({
        'schema_version': 1,
        'items': [record().item.toJson()],
        'settings': {'overdue_recovery_policy': 'unknown'},
      });
      final store = MemoryStore()..contents = source;
      final repository = LocalRepository(store);
      await expectLater(repository.getSettings(), throwsFormatException);
      await expectLater(repository.allItems(), throwsFormatException);
      await expectLater(
        repository.saveSettings(const LifestyleSettings()),
        throwsFormatException,
      );
      expect(store.contents, source);
    },
  );
}
