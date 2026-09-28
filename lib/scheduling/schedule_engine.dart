import '../storage/inbox_item.dart';
import '../storage/lifestyle_settings.dart';
import 'japanese_holidays.dart';

/// Converts UTC instants to local civil time and local wall time back to UTC.
/// DeviceZone follows the device's current time zone, including DST rules.
abstract interface class ScheduleZone {
  DateTime toLocal(DateTime instant);
  DateTime fromLocal(int year, int month, int day, int hour, int minute);
}

class DeviceZone implements ScheduleZone {
  const DeviceZone();

  @override
  DateTime toLocal(DateTime instant) => instant.toLocal();

  @override
  DateTime fromLocal(int year, int month, int day, int hour, int minute) =>
      DateTime(year, month, day, hour, minute).toUtc();
}

/// A deterministic zone for tests and callers with a known fixed offset.
class FixedOffsetZone implements ScheduleZone {
  const FixedOffsetZone(this.offset);

  final Duration offset;

  @override
  DateTime toLocal(DateTime instant) => instant.toUtc().add(offset);

  @override
  DateTime fromLocal(int year, int month, int day, int hour, int minute) =>
      DateTime.utc(year, month, day, hour, minute).subtract(offset);
}

enum NotificationContext {
  commute,
  afterHome,
  evening,
  nextDayEvening,
  holidayEve,
  holidayDay,
  holidayEvening,
  nextWeek;

  String get storageKey => switch (this) {
    commute => 'commute',
    afterHome => 'after_home',
    evening => 'evening',
    nextDayEvening => 'next_day_evening',
    holidayEve => 'holiday_eve',
    holidayDay => 'holiday_day',
    holidayEvening => 'holiday_evening',
    nextWeek => 'next_week',
  };
}

class Schedule {
  const Schedule(this.at, this.context, this.reason);

  /// UTC instant; storage serializes it as UTC as well.
  final DateTime at;
  final NotificationContext context;
  final String reason;
}

/// Pure scheduling policy. Every call receives the current instant explicitly.
class ScheduleEngine {
  const ScheduleEngine({
    this.zone = const DeviceZone(),
    this.holidays = const JapaneseHolidays(),
  });

  final ScheduleZone zone;
  final JapaneseHolidays holidays;

  Schedule initial(InboxItem item, LifestyleSettings settings, DateTime now) {
    final context = switch (item.category) {
      ItemCategory.read =>
        item.contentLength == ContentLength.long
            ? NotificationContext.holidayDay
            : NotificationContext.commute,
      ItemCategory.watch =>
        item.contentLength == ContentLength.long
            ? NotificationContext.holidayEvening
            : NotificationContext.evening,
      ItemCategory.go => NotificationContext.holidayEve,
      ItemCategory.buy => NotificationContext.holidayDay,
      ItemCategory.doTask => NotificationContext.afterHome,
      ItemCategory.idea => NotificationContext.nextWeek,
      ItemCategory.memo => NotificationContext.nextDayEvening,
    };
    return _next(
      context,
      settings,
      now,
      'initial:${item.category.name}:${item.contentLength.name}',
    );
  }

  Schedule snooze(InboxItem item, LifestyleSettings settings, DateTime now) {
    if (item.status != ItemStatus.active) {
      throw StateError('Only active items can be snoozed');
    }
    final context = switch (item.snoozeCount) {
      0 => NotificationContext.nextDayEvening,
      1 =>
        item.category == ItemCategory.watch
            ? NotificationContext.holidayEvening
            : NotificationContext.holidayDay,
      _ => NotificationContext.nextWeek,
    };
    return _next(context, settings, now, 'snooze:${item.snoozeCount + 1}');
  }

  /// Recalculation preserves an active item's current snooze stage.
  Schedule recalculate(
    InboxItem item,
    LifestyleSettings settings,
    DateTime now,
  ) => item.snoozeCount == 0
      ? initial(item, settings, now)
      : snooze(item.copyWith(snoozeCount: item.snoozeCount - 1), settings, now);

  Schedule _next(
    NotificationContext requested,
    LifestyleSettings settings,
    DateTime now,
    String source,
  ) {
    final local = zone.toLocal(now.toUtc());
    final today = DateTime.utc(local.year, local.month, local.day);
    final hasRestDays =
        settings.weekendsAreHolidays || settings.japaneseHolidays;
    final context = !hasRestDays && _isRestContext(requested)
        ? NotificationContext.nextWeek
        : requested;
    final minute = switch (context) {
      NotificationContext.commute => settings.commuteStartMinute,
      NotificationContext.afterHome => settings.afterHomeMinute,
      NotificationContext.holidayDay => 12 * 60,
      NotificationContext.holidayEvening => 20 * 60,
      _ => 21 * 60,
    };
    final startDay = switch (context) {
      NotificationContext.nextDayEvening => 1,
      NotificationContext.nextWeek => 7,
      _ => 0,
    };
    // One year is enough to locate any configured holiday/weekend. If official
    // data runs out, the holiday provider throws instead of guessing dates.
    for (var dayOffset = startDay; dayOffset < startDay + 370; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));
      if (!_eligible(date, context, settings)) continue;
      final candidate = zone.fromLocal(
        date.year,
        date.month,
        date.day,
        minute ~/ 60,
        minute % 60,
      );
      if (candidate.isAfter(now)) {
        return Schedule(
          candidate.toUtc(),
          context,
          context == requested
              ? '$source:${context.storageKey}'
              : '$source:no_rest_days:next_week',
        );
      }
    }
    throw StateError('No future notification date found');
  }

  bool _eligible(
    DateTime date,
    NotificationContext context,
    LifestyleSettings settings,
  ) => switch (context) {
    NotificationContext.commute ||
    NotificationContext.afterHome => !_restDay(date, settings),
    NotificationContext.holidayEve =>
      !_restDay(date, settings) &&
          _restDay(date.add(const Duration(days: 1)), settings),
    NotificationContext.holidayDay ||
    NotificationContext.holidayEvening => _restDay(date, settings),
    _ => true,
  };

  bool _restDay(DateTime date, LifestyleSettings settings) =>
      (settings.weekendsAreHolidays &&
          (date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday)) ||
      (settings.japaneseHolidays && holidays.isHoliday(date));

  bool _isRestContext(NotificationContext context) => switch (context) {
    NotificationContext.holidayEve ||
    NotificationContext.holidayDay ||
    NotificationContext.holidayEvening => true,
    _ => false,
  };
}
