import 'dart:io';

import 'package:atode_box/notifications/flutter_notification_port.dart';
import 'package:atode_box/notifications/notification_controller.dart';
import 'package:atode_box/notifications/notification_port.dart';
import 'package:atode_box/storage/inbox_item.dart';
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
  final requests = <int, LocalNotice>{};
  void Function(NoticeResponse)? callback;
  @override
  Future<void> initialize(void Function(NoticeResponse) onResponse) async =>
      callback = onResponse;
  @override
  Future<NoticeResponse?> launchResponse() async => null;
  @override
  Future<bool> permissionGranted() async => allowed;
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<List<PendingNotice>> pending() async => requests.values
      .map((notice) => PendingNotice(notice.id, notice.payload))
      .toList();
  @override
  Future<void> schedule(LocalNotice notice) async {
    if (failSchedule) throw const FileSystemException('OS scheduling failed');
    requests[notice.id] = notice;
  }

  @override
  Future<void> cancel(int id) async => requests.remove(id);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
