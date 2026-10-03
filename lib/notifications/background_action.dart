import 'dart:convert';

import '../scheduling/schedule_engine.dart';
import '../storage/inbox_item.dart';
import '../storage/lifestyle_settings.dart';

// Proposed v2 contract only. No production notification emits this payload.
const _maxCounter = 9007199254740991;

enum BackgroundAction { complete, snooze }

class NotificationActionToken {
  const NotificationActionToken._(
    this.itemId,
    this.notificationId,
    this.at,
    this.generation,
    this.incarnation,
    this.epoch,
  );

  final String itemId;
  final int notificationId;
  final DateTime at;
  final int generation;
  final String incarnation;
  final String epoch;

  static NotificationActionToken? parse(String? payload) {
    if (payload == null || payload.length > 2048) return null;
    try {
      final value = jsonDecode(payload);
      const keys = {
        'v',
        'id',
        'nid',
        'at',
        'generation',
        'incarnation',
        'epoch',
      };
      if (value is! Map<String, dynamic> ||
          value.length != keys.length ||
          !keys.every(value.containsKey) ||
          value['v'] is! int ||
          value['v'] != 2) {
        return null;
      }
      final id = value['id'];
      final nid = value['nid'];
      final at = value['at'];
      final generation = value['generation'];
      final incarnation = value['incarnation'];
      final epoch = value['epoch'];
      bool identifier(Object? text) =>
          text is String && text.isNotEmpty && text.length <= 256;
      if (!identifier(id) ||
          !identifier(incarnation) ||
          !identifier(epoch) ||
          nid is! int ||
          nid < 1 ||
          nid > 0x7fffffff ||
          generation is! int ||
          generation < 0 ||
          generation >= _maxCounter ||
          at is! String) {
        return null;
      }
      final instant = DateTime.tryParse(at);
      // A canonical UTC round trip also rejects normalized invalid dates.
      if (instant == null ||
          !instant.isUtc ||
          instant.toIso8601String() != at) {
        return null;
      }
      return NotificationActionToken._(
        id as String,
        nid,
        instant,
        generation,
        incarnation as String,
        epoch as String,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Incarnation and epoch are supplied by a future durable adapter. This class
/// does not generate them or detect backup restoration.
class NotificationActionRecord {
  const NotificationActionRecord({
    required this.item,
    required this.generation,
    required this.incarnation,
    required this.epoch,
  });

  final InboxItem item;
  final int generation;
  final String incarnation;
  final String epoch;
}

class NotificationActionSnapshot {
  const NotificationActionSnapshot({
    required this.revision,
    required this.record,
    required this.settings,
  });

  final int revision;
  final NotificationActionRecord? record;
  final LifestyleSettings settings;
}

/// Pure domain transition. The schedule policy is reused, not duplicated.
NotificationActionRecord? reduceBackgroundAction({
  required NotificationActionSnapshot snapshot,
  required NotificationActionToken token,
  required BackgroundAction action,
  required ScheduleEngine scheduler,
  required DateTime now,
}) {
  final previous = snapshot.record;
  if (previous == null) return null;
  final item = previous.item;
  if (item.id != token.itemId ||
      item.notificationId != token.notificationId ||
      item.status != ItemStatus.active ||
      item.nextNotifyAt?.isAtSameMomentAs(token.at) != true ||
      previous.generation != token.generation ||
      previous.incarnation != token.incarnation ||
      previous.epoch != token.epoch) {
    return null;
  }
  final InboxItem updated;
  switch (action) {
    case BackgroundAction.complete:
      updated = item.completed();
    case BackgroundAction.snooze:
      final schedule = scheduler.snooze(item, snapshot.settings, now);
      updated = item.snoozed(
        schedule.at,
        notificationContext: schedule.context.storageKey,
        reason: schedule.reason,
      );
  }
  return NotificationActionRecord(
    item: updated,
    generation: previous.generation + 1,
    incarnation: previous.incarnation,
    epoch: previous.epoch,
  );
}

/// Future adapter contract; LocalRepository deliberately does not implement it.
abstract interface class NotificationActionTransactions {
  /// Fresh committed record and settings from the SAME document revision.
  Future<NotificationActionSnapshot> read(String itemId);

  /// Atomically compare the global document revision AND previous token state,
  /// replace only this item, advance document revision and mark OS effects dirty.
  /// Every foreground/background writer must participate in the same revision
  /// protocol. False means no writes; exceptions may mean an unknown commit.
  /// Do not store an old whole-document snapshot or perform OS work here.
  Future<bool> compareAndSwap({
    required int expectedRevision,
    required NotificationActionRecord previous,
    required NotificationActionRecord next,
  });
}

enum BackgroundActionResult { ignored, applied, conflict }

/// Unconnected preparation service. Bounded CAS retry reloads settings/state;
/// exceptions propagate without retrying an ambiguously completed write.
Future<BackgroundActionResult> prepareBackgroundAction({
  required NotificationActionTransactions transactions,
  required String actionId,
  required String? payload,
  required DateTime now,
  ScheduleEngine scheduler = const ScheduleEngine(),
}) async {
  final action = switch (actionId) {
    'complete' => BackgroundAction.complete,
    'snooze' => BackgroundAction.snooze,
    _ => null,
  };
  final token = NotificationActionToken.parse(payload);
  if (action == null || token == null) return BackgroundActionResult.ignored;
  for (var attempt = 0; attempt < 3; attempt++) {
    final snapshot = await transactions.read(token.itemId);
    final next = reduceBackgroundAction(
      snapshot: snapshot,
      token: token,
      action: action,
      scheduler: scheduler,
      now: now,
    );
    if (next == null) return BackgroundActionResult.ignored;
    if (await transactions.compareAndSwap(
      expectedRevision: snapshot.revision,
      previous: snapshot.record!,
      next: next,
    )) {
      return BackgroundActionResult.applied;
    }
  }
  return BackgroundActionResult.conflict;
}
