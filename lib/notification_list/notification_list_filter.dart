import '../scheduling/japanese_holidays.dart';
import '../scheduling/schedule_engine.dart';
import '../storage/inbox_item.dart';
import '../storage/lifestyle_settings.dart';

enum NotificationListFilter {
  today,
  tomorrowOnward,
  holidays,
  nextWeek,
  completed,
}

extension NotificationListFilterLabel on NotificationListFilter {
  String get label => switch (this) {
    NotificationListFilter.today => '今日',
    NotificationListFilter.tomorrowOnward => '明日以降',
    NotificationListFilter.holidays => '休日',
    NotificationListFilter.nextWeek => '1週間後以降',
    NotificationListFilter.completed => '完了済み',
  };
}

/// Uses civil dates in the device zone; overdue active items remain visible today.
class NotificationListQuery {
  const NotificationListQuery({
    this.zone = const DeviceZone(),
    this.holidays = const JapaneseHolidays(),
  });

  final ScheduleZone zone;
  final JapaneseHolidays holidays;

  List<InboxItem> select(
    Iterable<InboxItem> items,
    NotificationListFilter filter,
    LifestyleSettings settings,
    DateTime now,
  ) {
    final today = _civil(zone.toLocal(now));
    final weekStart = today.add(const Duration(days: 7));
    final result = items.where((item) {
      if (filter == NotificationListFilter.completed) {
        return item.status == ItemStatus.completed;
      }
      if (item.status != ItemStatus.active || item.nextNotifyAt == null) {
        return false;
      }
      final date = _civil(zone.toLocal(item.nextNotifyAt!));
      return switch (filter) {
        NotificationListFilter.today => !date.isAfter(today),
        NotificationListFilter.tomorrowOnward => date.isAfter(today),
        NotificationListFilter.holidays => _isRestDay(date, settings),
        NotificationListFilter.nextWeek => !date.isBefore(weekStart),
        NotificationListFilter.completed => false,
      };
    }).toList();
    result.sort((a, b) {
      final aTime = filter == NotificationListFilter.completed
          ? a.savedAt
          : a.nextNotifyAt!;
      final bTime = filter == NotificationListFilter.completed
          ? b.savedAt
          : b.nextNotifyAt!;
      return filter == NotificationListFilter.completed
          ? bTime.compareTo(aTime)
          : aTime.compareTo(bTime);
    });
    return result;
  }

  DateTime _civil(DateTime time) =>
      DateTime.utc(time.year, time.month, time.day);

  bool _isRestDay(DateTime date, LifestyleSettings settings) =>
      (settings.weekendsAreHolidays &&
          (date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday)) ||
      (settings.japaneseHolidays && holidays.isHoliday(date));
}
