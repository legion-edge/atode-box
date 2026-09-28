import '../scheduling/schedule_engine.dart';
import '../storage/inbox_item.dart';
import '../storage/local_repository.dart';
import 'flutter_notification_port.dart';
import 'notification_port.dart';

/// Makes OS requests converge on the durable item state after each mutation.
class NotificationController {
  NotificationController(
    this.repository,
    this.port, {
    required this.onOpen,
    required this.onError,
  });

  final LocalRepository repository;
  final NotificationPort port;
  final void Function(InboxItem) onOpen;
  final void Function(String) onError;
  Future<void> _tail = Future.value();
  Future<void> _syncTail = Future.value();

  Future<void> initialize() async {
    await port.initialize((response) {
      handle(response).catchError((Object _) {
        onError('通知操作を反映できませんでした。アプリで確認してください');
      });
    });
    final launch = await port.launchResponse();
    if (launch != null) {
      try {
        await handle(launch);
      } catch (_) {
        onError('通知操作を反映できませんでした。アプリで確認してください');
      }
    }
    await sync();
  }

  Future<void> handle(NoticeResponse response) {
    final result = _tail.then((_) => _handle(response));
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _handle(NoticeResponse response) async {
    final payload = response.payload;
    if (payload == null) return;
    final divider = payload.indexOf('|');
    if (divider < 1) return;
    final item = await repository.getItem(payload.substring(0, divider));
    if (item == null ||
        item.status != ItemStatus.active ||
        item.nextNotifyAt?.toUtc().toIso8601String() !=
            payload.substring(divider + 1)) {
      return; // A removed, completed, or superseded notification.
    }
    switch (response.action) {
      case FlutterNotificationPort.open:
      case '':
        onOpen(item);
        return;
      case FlutterNotificationPort.complete:
        await repository.updateItem(item.completed());
        try {
          await sync();
        } catch (_) {
          onError('完了は保存しました。通知の更新は次回起動時に再試行します');
        }
        return;
      case FlutterNotificationPort.snooze:
        await repository.snoozeItem(
          item.id,
          const ScheduleEngine(),
          DateTime.now(),
        );
        try {
          await sync();
        } catch (_) {
          onError('あとでは保存しました。通知の更新は次回起動時に再試行します');
        }
        return;
      default:
        return;
    }
  }

  Future<bool> requestPermission() async {
    final allowed = await port.requestPermission();
    if (allowed) await sync();
    return allowed;
  }

  Future<bool> permissionGranted() => port.permissionGranted();

  Future<void> sync() {
    final result = _syncTail.then((_) => _performSync());
    _syncTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _performSync() async {
    await repository.adjustForTimeZone(const ScheduleEngine(), DateTime.now());
    final items = await repository.allItems();
    final pending = await port.pending();
    final pendingById = {for (final request in pending) request.id: request};
    final allowed = await port.permissionGranted();
    final now = DateTime.now();
    final desired = allowed
        ? (items
                  .where(
                    (item) =>
                        item.status == ItemStatus.active &&
                        item.notificationId != null &&
                        item.nextNotifyAt != null &&
                        item.nextNotifyAt!.isAfter(now),
                  )
                  .map(noticeFor)
                  .toList()
                ..sort((a, b) => a.at.compareTo(b.at)))
              .take(64)
              .toList()
        : <LocalNotice>[];
    final wanted = {for (final notice in desired) notice.id: notice};
    for (final request in pending) {
      if (wanted[request.id] == null ||
          wanted[request.id]!.payload != request.payload) {
        await port.cancel(request.id);
      }
    }
    if (!allowed) return;
    for (final notice in desired) {
      if (pendingById[notice.id]?.payload != notice.payload) {
        await port.schedule(notice);
      }
    }
  }
}
