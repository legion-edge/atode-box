import 'package:atode_box/notification_list/notification_list_filter.dart';
import 'package:atode_box/scheduling/schedule_engine.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:flutter_test/flutter_test.dart';

InboxItem item(
  String id,
  DateTime at, {
  ItemStatus status = ItemStatus.active,
}) => InboxItem(
  id: id,
  originalText: id,
  savedAt: DateTime.utc(2026, 9, 1),
  nextNotifyAt: at,
  status: status,
);

void main() {
  const query = NotificationListQuery(
    zone: FixedOffsetZone(Duration(hours: 9)),
  );
  const settings = LifestyleSettings();
  final now = DateTime.utc(2026, 9, 30, 14, 30); // 23:30 local

  test('端末暦日の23:59と翌日00:00を分け、期限超過も今日に残す', () {
    final items = [
      item('overdue', DateTime.utc(2026, 9, 29, 12)),
      item('today', DateTime.utc(2026, 9, 30, 14, 59)),
      item('tomorrow', DateTime.utc(2026, 9, 30, 15)),
    ];
    expect(
      query
          .select(items, NotificationListFilter.today, settings, now)
          .map((e) => e.id),
      ['overdue', 'today'],
    );
    expect(
      query
          .select(items, NotificationListFilter.tomorrowOnward, settings, now)
          .map((e) => e.id),
      ['tomorrow'],
    );
  });

  test('1週間後は7暦日目の00:00からで、完了と削除はactiveに混ぜない', () {
    final items = [
      item('day6', DateTime.utc(2026, 10, 6, 14, 59)),
      item('day7', DateTime.utc(2026, 10, 6, 15)),
      item(
        'completed',
        DateTime.utc(2026, 10, 6, 15),
        status: ItemStatus.completed,
      ),
      item(
        'deleted',
        DateTime.utc(2026, 10, 6, 15),
        status: ItemStatus.deleted,
      ),
    ];
    expect(
      query
          .select(items, NotificationListFilter.nextWeek, settings, now)
          .map((e) => e.id),
      ['day7'],
    );
    expect(
      query
          .select(items, NotificationListFilter.completed, settings, now)
          .map((e) => e.id),
      ['completed'],
    );
  });

  test('休日は設定済みの土日と日本の祝日を現地日付で判定する', () {
    final items = [
      item('friday', DateTime.utc(2026, 10, 2, 12)),
      item('saturday', DateTime.utc(2026, 10, 2, 15)),
      item('holiday', DateTime.utc(2026, 10, 11, 15)), // Oct 12 holiday
    ];
    expect(
      query
          .select(items, NotificationListFilter.holidays, settings, now)
          .map((e) => e.id),
      ['saturday', 'holiday'],
    );
    expect(
      query
          .select(
            items,
            NotificationListFilter.holidays,
            settings.copyWith(weekendsAreHolidays: false),
            now,
          )
          .map((e) => e.id),
      ['holiday'],
    );
    expect(
      query
          .select(
            items,
            NotificationListFilter.holidays,
            settings.copyWith(japaneseHolidays: false),
            now,
          )
          .map((e) => e.id),
      ['saturday'],
    );
  });

  test('あとで後の現在のnextNotifyAtで選ぶ', () {
    final original = item('later', DateTime.utc(2026, 9, 30, 14));
    final snoozed = original.snoozed(DateTime.utc(2026, 10, 1, 12));
    expect(
      query.select([snoozed], NotificationListFilter.today, settings, now),
      isEmpty,
    );
    expect(
      query
          .select(
            [snoozed],
            NotificationListFilter.tomorrowOnward,
            settings,
            now,
          )
          .single
          .id,
      'later',
    );
  });

  test('次回日時がない旧active項目は今日に残し、追加フィルターには混ぜない', () {
    final legacy = InboxItem(
      id: 'legacy',
      originalText: '古いメモ',
      savedAt: DateTime.utc(2026, 9, 1),
    );
    expect(
      query
          .select([legacy], NotificationListFilter.today, settings, now)
          .single
          .id,
      'legacy',
    );
    for (final filter in [
      NotificationListFilter.tomorrowOnward,
      NotificationListFilter.holidays,
      NotificationListFilter.nextWeek,
      NotificationListFilter.completed,
    ]) {
      expect(query.select([legacy], filter, settings, now), isEmpty);
    }
  });
}
