import '../scheduling/schedule_engine.dart';
import '../storage/inbox_item.dart';
import '../storage/lifestyle_settings.dart';
import 'background_action.dart';

enum RecoveredNoticeDelivery { scheduleFuture, notifyOnRecovery }

class OverdueRecoveryTransition {
  const OverdueRecoveryTransition({required this.next, required this.delivery});
  final NotificationActionRecord next;
  final RecoveredNoticeDelivery delivery;
}

/// Pure transition for independently CONFIRMED non-delivery of this exact token.
/// Pending/displayed absence alone must never set nonDeliveryConfirmed=true.
/// A future native worker must revalidate proof and settings in the transaction,
/// then commit generation/outbox atomically. There is no production caller.
OverdueRecoveryTransition? recoverConfirmedOverdueNotice({
  required NotificationActionRecord record,
  required NotificationActionToken token,
  required bool nonDeliveryConfirmed,
  required LifestyleSettings settings,
  required DateTime now,
  ScheduleEngine scheduler = const ScheduleEngine(),
}) {
  final item = record.item;
  if (!nonDeliveryConfirmed ||
      item.status != ItemStatus.active ||
      item.nextNotifyAt == null ||
      !item.nextNotifyAt!.isBefore(now) ||
      item.id != token.itemId ||
      item.notificationId != token.notificationId ||
      item.nextNotifyAt?.isAtSameMomentAs(token.at) != true ||
      record.generation != token.generation ||
      record.incarnation != token.incarnation ||
      record.epoch != token.epoch) {
    return null;
  }
  final InboxItem updated;
  final RecoveredNoticeDelivery delivery;
  switch (settings.overdueRecoveryPolicy) {
    case OverdueRecoveryPolicy.nextRegularSlot:
      final schedule = scheduler.recalculate(item, settings, now);
      if (!schedule.at.isAfter(now)) {
        throw StateError('Recovery must select a future regular slot');
      }
      updated = item.copyWith(
        nextNotifyAt: schedule.at,
        context: schedule.context.storageKey,
        scheduleReason: 'recovery:next_regular_slot:${schedule.reason}',
      );
      delivery = RecoveredNoticeDelivery.scheduleFuture;
    case OverdueRecoveryPolicy.notifyOnRecovery:
      updated = item.copyWith(
        nextNotifyAt: now.toUtc(),
        context: null,
        scheduleReason: 'recovery:notify_on_recovery',
      );
      // A future native worker must use an immediate OS delivery operation;
      // passing at==now into the existing future-only sync would lose this work.
      delivery = RecoveredNoticeDelivery.notifyOnRecovery;
  }
  return OverdueRecoveryTransition(
    next: NotificationActionRecord(
      item: updated,
      generation: record.generation + 1,
      incarnation: record.incarnation,
      epoch: record.epoch,
    ),
    delivery: delivery,
  );
}
