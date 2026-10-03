import 'dart:io';

import 'package:atode_box/notifications/flutter_notification_port.dart';
import 'package:atode_box/notifications/notification_controller.dart';
import 'package:atode_box/notifications/notification_port.dart';
import 'package:atode_box/scheduling/schedule_engine.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStore implements DocumentStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String contents) async => value = contents;
}

class FakePort implements NotificationPort {
  bool allowed = true;
  bool failSchedule = false;
  bool failCancel = false;
  final requests = <int, LocalNotice>{};
  void Function(NoticeResponse)? callback;
  NoticeResponse? launchNotice;
  bool deliverCallbackOnLaunch = false;
  @override
  Future<void> initialize(void Function(NoticeResponse) onResponse) async =>
      callback = onResponse;
  @override
  Future<NoticeResponse?> launchResponse() async {
    if (deliverCallbackOnLaunch && launchNotice != null) {
      callback?.call(launchNotice!);
    }
    return launchNotice;
  }

  @override
  Future<bool> permissionGranted() async => allowed;
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<List<PendingNotice>> pending() async => requests.values
      .map(
        (notice) => PendingNotice(
          notice.id,
          notice.payload,
          title: notice.title,
          body: notice.body,
        ),
      )
      .toList();
  @override
  Future<void> schedule(LocalNotice notice) async {
    if (failSchedule) throw const FileSystemException('OS scheduling failed');
    requests[notice.id] = notice;
  }

  @override
  Future<void> cancel(int id) async {
    if (failCancel) throw const FileSystemException('OS cancellation failed');
    requests.remove(id);
  }
}

/// Interleave a durable mutation after the controller reads a snapshot.
class InterleavingRepository extends LocalRepository {
  InterleavingRepository(super.store);
  Future<void> Function()? afterRead;

  @override
  Future<InboxItem?> getItem(String id) async {
    final snapshot = await super.getItem(id);
    final action = afterRead;
    afterRead = null;
    await action?.call();
    return snapshot;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final action in [
    FlutterNotificationPort.complete,
    FlutterNotificationPort.snooze,
  ]) {
    for (final mutation in ['metadata', 'reschedule', 'delete']) {
      test('通知$actionの照合後に$mutationが入っても最新保存を失わない', () async {
        final instant = DateTime.utc(2026, 10, 1);
        const scheduler = ScheduleEngine(
          zone: FixedOffsetZone(Duration(hours: 9)),
        );
        final repo = InterleavingRepository(MemoryStore());
        final port = FakePort();
        await repo.saveItem(
          InboxItem(
            id: 'race',
            originalText: '記事',
            savedAt: instant,
            category: ItemCategory.read,
          ),
          scheduler: scheduler,
          now: instant,
        );
        final item = (await repo.getItem('race'))!;
        final controller = NotificationController(
          repo,
          port,
          onOpen: (_) {},
          onError: (_) {},
          now: () => instant,
        );
        await controller.sync();
        repo.afterRead = () async {
          if (mutation == 'delete') {
            await repo.deleteItem(item.id);
          } else {
            await repo.editItem(
              item.id,
              title: '最新タイトル',
              url: 'https://example.com/new',
              category: mutation == 'reschedule'
                  ? ItemCategory.watch
                  : ItemCategory.read,
              scheduler: scheduler,
              now: instant,
            );
          }
        };
        await controller.handle(
          NoticeResponse(action, noticeFor(item).payload),
        );
        final result = (await repo.getItem(item.id))!;
        expect(result.originalText, item.originalText);
        if (mutation == 'delete') {
          expect(result.status, ItemStatus.deleted);
          expect(result.snoozeCount, 0);
        } else {
          expect(result.title, '最新タイトル');
          expect(result.url, 'https://example.com/new');
          if (mutation == 'reschedule') {
            expect(result.status, ItemStatus.active);
            expect(result.category, ItemCategory.watch);
            expect(result.snoozeCount, 0);
            expect(result.nextNotifyAt, isNot(item.nextNotifyAt));
          } else {
            expect(
              result.status,
              action == FlutterNotificationPort.complete
                  ? ItemStatus.completed
                  : ItemStatus.active,
            );
            expect(
              result.snoozeCount,
              action == FlutterNotificationPort.snooze ? 1 : 0,
            );
          }
        }
      });
    }
  }

  test('カテゴリ編集で予定が同時刻でも通知文面を更新し、削除後は古いアクションを無視する', () async {
    final instant = DateTime.utc(2026, 10, 1);
    const scheduler = ScheduleEngine(zone: FixedOffsetZone(Duration(hours: 9)));
    final repo = LocalRepository(MemoryStore());
    final port = FakePort();
    await repo.saveSettings(const LifestyleSettings(afterHomeMinute: 21 * 60));
    await repo.saveItem(
      InboxItem(
        id: 'same',
        originalText: '動画',
        savedAt: instant,
        category: ItemCategory.watch,
      ),
      scheduler: scheduler,
      now: instant,
    );
    final before = (await repo.getItem('same'))!;
    final controller = NotificationController(
      repo,
      port,
      onOpen: (_) {},
      onError: (_) {},
      now: () => instant,
    );
    await controller.sync();
    expect(port.requests[before.notificationId]!.title, '見る');
    final edited = await repo.editItem(
      before.id,
      title: null,
      url: '',
      category: ItemCategory.doTask,
      scheduler: scheduler,
      now: instant,
    );
    expect(edited.nextNotifyAt, before.nextNotifyAt);
    port.failCancel = true;
    await expectLater(controller.sync(), throwsA(isA<FileSystemException>()));
    expect(port.requests[edited.notificationId]!.title, '見る');
    port.failCancel = false;
    await controller.sync();
    expect(port.requests[edited.notificationId]!.title, 'やる');
    await repo.deleteItem(edited.id);
    await controller.sync();
    expect(port.requests, isEmpty);
    await controller.handle(
      NoticeResponse(FlutterNotificationPort.snooze, noticeFor(edited).payload),
    );
    expect((await repo.getItem(edited.id))!.status, ItemStatus.deleted);
  });

  test('予定を過ぎても一致する未配信予約を保持し、予約なし過去項目は再配信しない', () async {
    final repository = LocalRepository(MemoryStore());
    final port = FakePort();
    final instant = DateTime.utc(2026, 10, 2, 17, 36);
    final due = instant.subtract(const Duration(minutes: 1));
    for (final id in ['pending', 'delivered']) {
      await repository.saveItem(
        InboxItem(
          id: id,
          originalText: id,
          savedAt: due,
          nextNotifyAt: due,
          category: ItemCategory.read,
        ),
      );
    }
    final pending = (await repository.getItem('pending'))!;
    port.requests[pending.notificationId!] = noticeFor(pending);
    final controller = NotificationController(
      repository,
      port,
      onOpen: (_) {},
      onError: (_) {},
      now: () => instant,
    );
    await controller.sync();
    expect(port.requests.keys, [pending.notificationId]);
    expect((await repository.getItem('pending'))!.status, ItemStatus.active);
  });

  test('注入時計が予定を越える復帰でも既存予約を保持する', () async {
    var instant = DateTime.utc(2026, 10, 2, 17, 34);
    final repository = LocalRepository(MemoryStore());
    final port = FakePort();
    await repository.saveItem(
      InboxItem(
        id: 'late',
        originalText: '記事',
        savedAt: instant,
        nextNotifyAt: instant.add(const Duration(minutes: 1)),
      ),
    );
    final controller = NotificationController(
      repository,
      port,
      onOpen: (_) {},
      onError: (_) {},
      now: () => instant,
    );
    await controller.sync();
    final payload = port.requests.values.single.payload;
    instant = instant.add(const Duration(minutes: 2));
    await controller.sync();
    expect(port.requests.values.single.payload, payload);
    // Simulate delivery: a later sync must not recreate the past reservation.
    port.requests.clear();
    await controller.sync();
    expect(port.requests, isEmpty);
  });

  test('過去itemと不一致payloadの既存予約は取消し再登録しない', () async {
    final instant = DateTime.utc(2026, 10, 2, 17, 36);
    final repository = LocalRepository(MemoryStore());
    final port = FakePort();
    await repository.saveItem(
      InboxItem(
        id: 'a',
        originalText: '記事',
        savedAt: instant,
        nextNotifyAt: instant.subtract(const Duration(minutes: 1)),
      ),
    );
    final item = (await repository.getItem('a'))!;
    port.requests[item.notificationId!] = noticeFor(
      item.copyWith(nextNotifyAt: instant.subtract(const Duration(minutes: 2))),
    );
    final controller = NotificationController(
      repository,
      port,
      onOpen: (_) {},
      onError: (_) {},
      now: () => instant,
    );
    await controller.sync();
    expect(port.requests, isEmpty);
    expect((await repository.getItem('a'))!.status, ItemStatus.active);
  });

  for (final status in [ItemStatus.completed, ItemStatus.deleted]) {
    test('過去の既存予約でも${status.name}なら取消す', () async {
      final instant = DateTime.utc(2026, 10, 2, 17, 36);
      final repository = LocalRepository(MemoryStore());
      final port = FakePort();
      await repository.saveItem(
        InboxItem(
          id: 'a',
          originalText: '記事',
          savedAt: instant,
          nextNotifyAt: instant.subtract(const Duration(minutes: 1)),
        ),
      );
      final item = (await repository.getItem('a'))!;
      port.requests[item.notificationId!] = noticeFor(item);
      await repository.updateItem(item.copyWith(status: status));
      final controller = NotificationController(
        repository,
        port,
        onOpen: (_) {},
        onError: (_) {},
        now: () => instant,
      );
      await controller.sync();
      expect(port.requests, isEmpty);
    });
  }

  test('過去の既存予約をあとですると古いpayloadを次回へ差し替える', () async {
    final instant = DateTime.utc(2026, 10, 2, 17, 36);
    final repository = LocalRepository(MemoryStore());
    final port = FakePort();
    await repository.saveItem(
      InboxItem(
        id: 'a',
        originalText: '記事',
        savedAt: instant,
        nextNotifyAt: instant.subtract(const Duration(minutes: 1)),
      ),
    );
    final item = (await repository.getItem('a'))!;
    final oldNotice = noticeFor(item);
    port.requests[item.notificationId!] = oldNotice;
    final controller = NotificationController(
      repository,
      port,
      onOpen: (_) {},
      onError: (_) {},
      now: () => instant,
    );
    await controller.handle(
      NoticeResponse(FlutterNotificationPort.snooze, oldNotice.payload),
    );
    final updated = (await repository.getItem('a'))!;
    expect(updated.snoozeCount, 1);
    expect(port.requests.values.single.payload, noticeFor(updated).payload);
    expect(port.requests.values.single.payload, isNot(oldNotice.payload));
    expect(updated.nextNotifyAt!.isAfter(instant), isTrue);
  });

  test('拒否中は過去の一致予約も取消し、再許可で過去を再配信しない', () async {
    final instant = DateTime.utc(2026, 10, 2, 17, 36);
    final repository = LocalRepository(MemoryStore());
    final port = FakePort()..allowed = false;
    await repository.saveItem(
      InboxItem(
        id: 'a',
        originalText: '記事',
        savedAt: instant,
        nextNotifyAt: instant.subtract(const Duration(minutes: 1)),
      ),
    );
    final item = (await repository.getItem('a'))!;
    port.requests[item.notificationId!] = noticeFor(item);
    final controller = NotificationController(
      repository,
      port,
      onOpen: (_) {},
      onError: (_) {},
      now: () => instant,
    );
    await controller.sync();
    expect(port.requests, isEmpty);
    port.allowed = true;
    await controller.sync();
    expect(port.requests, isEmpty);
  });

  test('過去の保持分も64件枠に含め、配信済みの空きへ未来予約を入れる', () async {
    final instant = DateTime.utc(2026, 10, 2, 17, 36);
    final repository = LocalRepository(MemoryStore());
    final port = FakePort();
    for (var index = 0; index < 65; index++) {
      final at = instant.add(Duration(minutes: index == 64 ? 1 : -1));
      await repository.saveItem(
        InboxItem(
          id: '$index',
          originalText: '記事',
          savedAt: instant,
          nextNotifyAt: at,
        ),
      );
      final item = (await repository.getItem('$index'))!;
      if (index < 64) port.requests[item.notificationId!] = noticeFor(item);
    }
    final future = (await repository.getItem('64'))!;
    final controller = NotificationController(
      repository,
      port,
      onOpen: (_) {},
      onError: (_) {},
      now: () => instant,
    );
    await controller.sync();
    expect(port.requests.length, 64);
    expect(port.requests.containsKey(future.notificationId), isFalse);
    final deliveredId = port.requests.keys.first;
    port.requests.remove(deliveredId);
    await controller.sync();
    expect(port.requests.length, 64);
    expect(port.requests.containsKey(future.notificationId), isTrue);
    expect(port.requests.containsKey(deliveredId), isFalse);
  });

  Future<(LocalRepository, FakePort, NotificationController, List<InboxItem>)>
  setup({bool allowed = true}) async {
    final repository = LocalRepository(MemoryStore());
    final port = FakePort()..allowed = allowed;
    final opened = <InboxItem>[];
    final controller = NotificationController(
      repository,
      port,
      onOpen: opened.add,
      onError: (_) {},
    );
    await controller.initialize();
    return (repository, port, controller, opened);
  }

  Future<InboxItem> add(
    LocalRepository repository,
    String id,
    ItemCategory category,
  ) async {
    await repository.saveItem(
      InboxItem(
        id: id,
        originalText: '保存 $id',
        savedAt: DateTime.now(),
        category: category,
        nextNotifyAt: DateTime.now().add(const Duration(days: 2)),
      ),
    );
    return (await repository.getItem(id))!;
  }

  test('権限拒否でも保存でき、許可後に予約を回復する', () async {
    final (repository, port, controller, _) = await setup(allowed: false);
    final item = await add(repository, 'a', ItemCategory.read);
    await controller.sync();
    expect(port.requests, isEmpty);
    expect((await repository.getItem('a'))!.status, ItemStatus.active);
    port.allowed = true;
    await controller.sync();
    expect(port.requests[item.notificationId]!.title, '読む');
    expect(port.requests[item.notificationId]!.body, contains('読んで'));
  });

  test('開くはactive維持、完了は予約を消し、古い操作は無視する', () async {
    final (repository, port, controller, opened) = await setup();
    final item = await add(repository, 'a', ItemCategory.watch);
    await controller.sync();
    final payload = port.requests[item.notificationId]!.payload;
    await controller.handle(
      NoticeResponse(FlutterNotificationPort.open, payload),
    );
    expect(opened.single.id, 'a');
    expect((await repository.getItem('a'))!.status, ItemStatus.active);
    await controller.handle(
      NoticeResponse(FlutterNotificationPort.complete, payload),
    );
    expect((await repository.getItem('a'))!.status, ItemStatus.completed);
    expect(port.requests, isEmpty);
    await controller.handle(
      NoticeResponse(FlutterNotificationPort.snooze, payload),
    );
    expect((await repository.getItem('a'))!.snoozeCount, 0);
  });

  test('あとでは1回だけ永続更新し、次回予約を差し替える', () async {
    final (repository, port, controller, _) = await setup();
    final item = await add(repository, 'a', ItemCategory.idea);
    await controller.sync();
    final oldPayload = port.requests[item.notificationId]!.payload;
    await controller.handle(
      NoticeResponse(FlutterNotificationPort.snooze, oldPayload),
    );
    final updated = (await repository.getItem('a'))!;
    expect(updated.status, ItemStatus.active);
    expect(updated.snoozeCount, 1);
    expect(port.requests[item.notificationId]!.payload, isNot(oldPayload));
    await controller.handle(
      NoticeResponse(FlutterNotificationPort.snooze, oldPayload),
    );
    expect((await repository.getItem('a'))!.snoozeCount, 1);
  });

  test('起動応答とcallbackの同じ「あとで」は1回だけ反映する', () async {
    final repository = LocalRepository(MemoryStore());
    final item = await add(repository, 'a', ItemCategory.idea);
    final port = FakePort()
      ..launchNotice = NoticeResponse(
        FlutterNotificationPort.snooze,
        noticeFor(item).payload,
      )
      ..deliverCallbackOnLaunch = true;
    final controller = NotificationController(
      repository,
      port,
      onOpen: (_) {},
      onError: (_) {},
    );

    await controller.initialize();

    final updated = (await repository.getItem('a'))!;
    expect(updated.snoozeCount, 1);
    expect(updated.nextNotifyAt, isNot(item.nextNotifyAt));
    expect(
      port.requests[item.notificationId]!.payload,
      noticeFor(updated).payload,
    );
  });

  test('OS予約失敗後も保存が残り、次回照合で再試行する', () async {
    final (repository, port, controller, _) = await setup();
    final item = await add(repository, 'a', ItemCategory.memo);
    port.failSchedule = true;
    await expectLater(controller.sync(), throwsA(isA<FileSystemException>()));
    expect((await repository.getItem('a'))!.status, ItemStatus.active);
    port.failSchedule = false;
    await controller.sync();
    expect(port.requests.containsKey(item.notificationId), isTrue);
  });
}
