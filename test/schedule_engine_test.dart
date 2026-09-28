import 'dart:io';

import 'package:atode_box/scheduling/japanese_holidays.dart';
import 'package:atode_box/scheduling/schedule_engine.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStore implements DocumentStore {
  String? value;
  bool fail = false;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String contents) async {
    if (fail) throw const FileSystemException('write failed');
    value = contents;
  }
}

void main() {
  const jst = FixedOffsetZone(Duration(hours: 9));
  const engine = ScheduleEngine(zone: jst);
  const settings = LifestyleSettings();
  final monday = DateTime.utc(2026, 9, 28, 1); // Monday 10:00 JST

  InboxItem item(
    String id,
    ItemCategory category, {
    ContentLength length = ContentLength.unspecified,
    ItemStatus status = ItemStatus.active,
    int snoozes = 0,
  }) => InboxItem(
    id: id,
    originalText: '原文',
    savedAt: monday,
    category: category,
    contentLength: length,
    status: status,
    snoozeCount: snoozes,
  );

  test('seven categories and explicit short/long map to fixed local slots', () {
    final cases =
        <(ItemCategory, ContentLength, NotificationContext, DateTime)>[
          (
            ItemCategory.read,
            ContentLength.unspecified,
            NotificationContext.commute,
            DateTime.utc(2026, 9, 28, 9),
          ),
          (
            ItemCategory.read,
            ContentLength.long,
            NotificationContext.holidayDay,
            DateTime.utc(2026, 10, 3, 3),
          ),
          (
            ItemCategory.watch,
            ContentLength.short,
            NotificationContext.evening,
            DateTime.utc(2026, 9, 28, 12),
          ),
          (
            ItemCategory.watch,
            ContentLength.long,
            NotificationContext.holidayEvening,
            DateTime.utc(2026, 10, 3, 11),
          ),
          (
            ItemCategory.go,
            ContentLength.unspecified,
            NotificationContext.holidayEve,
            DateTime.utc(2026, 10, 2, 12),
          ),
          (
            ItemCategory.buy,
            ContentLength.unspecified,
            NotificationContext.holidayDay,
            DateTime.utc(2026, 10, 3, 3),
          ),
          (
            ItemCategory.doTask,
            ContentLength.unspecified,
            NotificationContext.afterHome,
            DateTime.utc(2026, 9, 28, 10),
          ),
          (
            ItemCategory.idea,
            ContentLength.unspecified,
            NotificationContext.nextWeek,
            DateTime.utc(2026, 10, 5, 12),
          ),
          (
            ItemCategory.memo,
            ContentLength.unspecified,
            NotificationContext.nextDayEvening,
            DateTime.utc(2026, 9, 29, 12),
          ),
        ];
    for (final (category, length, context, expected) in cases) {
      final saved = item(category.name, category, length: length);
      final result = engine.initial(saved, settings, monday);
      expect(result.context, context);
      expect(result.at, expected);
      expect(engine.initial(saved, settings, monday).at, result.at);
      expect(result.at.isAfter(monday), isTrue);
    }
  });

  test('past slot moves forward and configured times are used', () {
    final now = DateTime.utc(2026, 9, 28, 12); // 21:00 JST
    final custom = const LifestyleSettings(
      commuteStartMinute: 17 * 60 + 30,
      afterHomeMinute: 20 * 60,
    );
    expect(
      engine.initial(item('r', ItemCategory.read), custom, now).at,
      DateTime.utc(2026, 9, 29, 8, 30),
    );
    expect(
      engine.initial(item('d', ItemCategory.doTask), custom, now).at,
      DateTime.utc(2026, 9, 29, 11),
    );
    expect(
      engine.initial(item('w', ItemCategory.watch), custom, now).at,
      DateTime.utc(2026, 9, 29, 12),
    );
  });

  test(
    'official holidays, substitute day, citizens day and consecutive rest',
    () {
      const holidays = JapaneseHolidays();
      expect(holidays.isHoliday(DateTime.utc(2026, 9, 22)), isTrue);
      expect(holidays.isHoliday(DateTime.utc(2026, 5, 6)), isTrue);
      expect(holidays.isHoliday(DateTime.utc(2027, 3, 22)), isTrue);
      expect(holidays.isHoliday(DateTime.utc(2026, 9, 28)), isFalse);
      final friday = DateTime.utc(2026, 9, 18, 1);
      expect(
        engine.initial(item('g', ItemCategory.go), settings, friday).at,
        DateTime.utc(2026, 9, 18, 12),
      );
      final sundayNight = DateTime.utc(2026, 9, 20, 12);
      expect(
        engine.initial(item('b', ItemCategory.buy), settings, sundayNight).at,
        DateTime.utc(2026, 9, 21, 3),
      );
      // The weekday between two national holidays is also a rest day.
      final mondayNight = DateTime.utc(2026, 9, 21, 12);
      expect(
        engine.initial(item('b2', ItemCategory.buy), settings, mondayNight).at,
        DateTime.utc(2026, 9, 22, 3),
      );
    },
  );

  test('holiday toggle and weekend toggle are independent', () {
    final beforeHoliday = DateTime.utc(2026, 9, 22, 1);
    final holidayOnly = const LifestyleSettings(weekendsAreHolidays: false);
    expect(
      engine
          .initial(item('b', ItemCategory.buy), holidayOnly, beforeHoliday)
          .at,
      DateTime.utc(2026, 9, 22, 3),
    );
    final weekendsOnly = const LifestyleSettings(japaneseHolidays: false);
    expect(
      engine
          .initial(item('b', ItemCategory.buy), weekendsOnly, beforeHoliday)
          .at,
      DateTime.utc(2026, 9, 26, 3),
    );
    final neither = const LifestyleSettings(
      weekendsAreHolidays: false,
      japaneseHolidays: false,
    );
    final fallback = engine.initial(
      item('b', ItemCategory.buy),
      neither,
      beforeHoliday,
    );
    expect(fallback.context, NotificationContext.nextWeek);
    expect(fallback.at, DateTime.utc(2026, 9, 29, 12));
  });

  test('year crossing uses published 2027 New Year, unknown years fail', () {
    final now = DateTime.utc(2026, 12, 30, 1);
    expect(
      engine.initial(item('g', ItemCategory.go), settings, now).at,
      DateTime.utc(2026, 12, 31, 12),
    );
    expect(
      engine.initial(item('b', ItemCategory.buy), settings, now).at,
      DateTime.utc(2027, 1, 1, 3),
    );
    expect(
      () => const JapaneseHolidays().isHoliday(DateTime.utc(2028, 1, 1)),
      throwsRangeError,
    );
  });

  test('fixed offsets produce local wall time across UTC date boundaries', () {
    final instant = DateTime.utc(2026, 9, 28, 13);
    final plus14 = ScheduleEngine(
      zone: const FixedOffsetZone(Duration(hours: 14)),
    );
    final minus8 = ScheduleEngine(
      zone: const FixedOffsetZone(Duration(hours: -8)),
    );
    expect(
      plus14.initial(item('m', ItemCategory.memo), settings, instant).at,
      DateTime.utc(2026, 9, 30, 7),
    );
    expect(
      minus8.initial(item('m', ItemCategory.memo), settings, instant).at,
      DateTime.utc(2026, 9, 30, 5),
    );
  });

  test(
    'repeat snooze advances stages and keeps active status atomically',
    () async {
      final repo = LocalRepository(MemoryStore());
      await repo.saveItem(
        item('1', ItemCategory.watch),
        scheduler: engine,
        now: monday,
      );
      final first = await repo.snoozeItem('1', engine, monday);
      expect(first.status, ItemStatus.active);
      expect(first.snoozeCount, 1);
      expect(first.context, 'next_day_evening');
      expect(first.nextNotifyAt, DateTime.utc(2026, 9, 29, 12));
      final second = await repo.snoozeItem('1', engine, first.nextNotifyAt!);
      expect(second.snoozeCount, 2);
      expect(second.context, 'holiday_evening');
      expect(second.nextNotifyAt, DateTime.utc(2026, 10, 3, 11));
      final third = await repo.snoozeItem('1', engine, second.nextNotifyAt!);
      expect(third.snoozeCount, 3);
      expect(third.context, 'next_week');
      expect(third.nextNotifyAt, DateTime.utc(2026, 10, 10, 12));
      final reopened = await LocalRepository(repo.store).getItem('1');
      expect(reopened!.snoozeCount, 3);
      expect(reopened.nextNotifyAt, third.nextNotifyAt);
      await repo.updateItem(third.completed());
      await expectLater(repo.snoozeItem('1', engine, monday), throwsStateError);
    },
  );

  test('content length survives reload and failed snooze is atomic', () async {
    final store = MemoryStore();
    final repo = LocalRepository(store);
    await repo.saveItem(
      item('long', ItemCategory.read, length: ContentLength.long),
      scheduler: engine,
      now: monday,
    );
    final reloaded = (await LocalRepository(store).getItem('long'))!;
    expect(reloaded.contentLength, ContentLength.long);
    expect(reloaded.nextNotifyAt, DateTime.utc(2026, 10, 3, 3));
    expect(reloaded.scheduleReason, 'initial:read:long:holiday_day');
    store.fail = true;
    await expectLater(
      repo.snoozeItem('long', engine, monday),
      throwsA(isA<FileSystemException>()),
    );
    final unchanged = (await LocalRepository(store).getItem('long'))!;
    expect(unchanged.snoozeCount, 0);
    expect(unchanged.nextNotifyAt, reloaded.nextNotifyAt);
  });

  test(
    'settings save recalculates active items only and commits together',
    () async {
      final store = MemoryStore();
      final repo = LocalRepository(store);
      await repo.saveItem(
        item('active', ItemCategory.read),
        scheduler: engine,
        now: monday,
      );
      await repo.saveItem(
        item('done', ItemCategory.read, status: ItemStatus.completed),
        scheduler: engine,
        now: monday,
      );
      final beforeDone = (await repo.getItem('done'))!.nextNotifyAt;
      final changed = await repo.saveSettingsWithSchedules(
        const LifestyleSettings(commuteStartMinute: 17 * 60),
        engine,
        monday,
      );
      expect(changed.scheduleChanged, isTrue);
      expect(
        (await repo.getItem('active'))!.nextNotifyAt,
        DateTime.utc(2026, 9, 28, 8),
      );
      expect((await repo.getItem('done'))!.nextNotifyAt, beforeDone);
      final setup = await repo.saveSettingsWithSchedules(
        const LifestyleSettings(
          commuteStartMinute: 17 * 60,
          initialSetupComplete: true,
        ),
        engine,
        DateTime.utc(2026, 9, 29, 1),
      );
      expect(setup.scheduleChanged, isFalse);
      expect(
        (await repo.getItem('active'))!.nextNotifyAt,
        DateTime.utc(2026, 9, 28, 8),
      );
      store.fail = true;
      await expectLater(
        repo.saveSettingsWithSchedules(
          const LifestyleSettings(commuteStartMinute: 16 * 60),
          engine,
          monday,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect((await repo.getSettings()).commuteStartMinute, 17 * 60);
      expect(
        (await repo.getItem('active'))!.nextNotifyAt,
        DateTime.utc(2026, 9, 28, 8),
      );
    },
  );

  test('settings recalculation preserves a snoozed item stage', () async {
    final repo = LocalRepository(MemoryStore());
    await repo.saveItem(
      item('1', ItemCategory.read),
      scheduler: engine,
      now: monday,
    );
    await repo.snoozeItem('1', engine, monday);
    final changed = await repo.saveSettingsWithSchedules(
      const LifestyleSettings(weekendsAreHolidays: false),
      engine,
      monday,
    );
    expect(changed.scheduleChanged, isTrue);
    final updated = (await repo.getItem('1'))!;
    expect(updated.snoozeCount, 1);
    expect(updated.context, 'next_day_evening');
    expect(updated.nextNotifyAt, DateTime.utc(2026, 9, 29, 12));
  });
}
