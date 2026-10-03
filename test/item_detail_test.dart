import 'dart:io';

import 'package:atode_box/item_detail/item_detail_screen.dart';
import 'package:atode_box/scheduling/schedule_engine.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Store implements DocumentStore {
  String? data;
  bool fail = false;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String value) async {
    if (fail) throw const FileSystemException('failed');
    data = value;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 1);
  const zone = FixedOffsetZone(Duration(hours: 9));
  const scheduler = ScheduleEngine(zone: zone);
  InboxItem item({String text = '原文 https://example.com', String? url}) =>
      InboxItem(id: 'test', originalText: text, savedAt: now, url: url);

  test('編集と削除が再読込後も原文・IDを保持し、予定はカテゴリと一致', () async {
    final store = Store();
    final repo = LocalRepository(store);
    await repo.saveItem(item(), scheduler: scheduler, now: now);
    final initial = (await repo.getItem('test'))!;
    final edited = await repo.editItem(
      'test',
      title: 'タイトル',
      url: '',
      category: ItemCategory.read,
      scheduler: scheduler,
      now: now,
    );
    final reopened = (await LocalRepository(store).getItem('test'))!;
    expect(reopened.originalText, initial.originalText);
    expect(reopened.notificationId, initial.notificationId);
    expect(reopened.savedAt, initial.savedAt);
    expect(reopened.context, 'commute');
    expect(
      reopened.nextNotifyAt,
      scheduler.initial(edited, await repo.getSettings(), now).at,
    );
    expect(itemUrl(reopened), isNull);
    await repo.deleteItem('test');
    final deleted = (await LocalRepository(store).getItem('test'))!;
    expect(deleted.status, ItemStatus.deleted);
    expect(deleted.nextNotifyAt, isNull);
  });

  test('編集は直前のあとで・完了を上書きせず、失敗時も元の保存を保持', () async {
    final store = Store();
    final repo = LocalRepository(store);
    await repo.saveItem(item(), scheduler: scheduler, now: now);
    final snoozed = await repo.snoozeItem('test', scheduler, now);
    final edited = await repo.editItem(
      'test',
      title: null,
      url: '',
      category: ItemCategory.watch,
      scheduler: scheduler,
      now: now,
    );
    expect(edited.snoozeCount, snoozed.snoozeCount);
    expect(edited.context, 'next_day_evening');
    await repo.updateItem(edited.completed());
    final completed = await repo.editItem(
      'test',
      title: '完了後',
      url: '',
      category: ItemCategory.read,
      scheduler: scheduler,
      now: now,
    );
    expect(completed.status, ItemStatus.completed);
    expect(completed.nextNotifyAt, isNull);
    store.fail = true;
    await expectLater(
      repo.editItem(
        'test',
        title: '失敗',
        url: '',
        category: ItemCategory.idea,
        scheduler: scheduler,
        now: now,
      ),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      repo.deleteItem('test'),
      throwsA(isA<FileSystemException>()),
    );
    expect((await LocalRepository(store).getItem('test'))!.title, '完了後');
    expect((await repo.getItem('test'))!.status, ItemStatus.completed);
  });

  Future<LocalRepository> show(
    WidgetTester tester,
    InboxItem value, {
    Future<bool> Function(Uri)? open,
    Future<void> Function()? sync,
    Store? store,
  }) async {
    final repo = LocalRepository(store ?? Store());
    await repo.saveItem(value, scheduler: scheduler, now: now);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: ItemDetailScreen(
          key: ValueKey(value.originalText),
          item: (await repo.getItem(value.id))!,
          repository: repo,
          now: () => now,
          zone: zone,
          openUrl: open,
          syncNotifications: sync,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('URL有りだけ開く、外部遷移はactiveと予定を保持', (tester) async {
    Uri? opened;
    final repo = await show(
      tester,
      item(),
      open: (uri) async {
        opened = uri;
        return true;
      },
    );
    expect(find.textContaining('保存日時 2026年10月1日 09:00'), findsOneWidget);
    expect(find.text('通知コンテキスト：翌日夜'), findsOneWidget);
    final before = (await repo.getItem('test'))!;
    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://example.com');
    expect((await repo.getItem('test'))!.status, ItemStatus.active);
    expect((await repo.getItem('test'))!.nextNotifyAt, before.nextNotifyAt);
    await show(tester, item(text: 'URLなし'));
    expect(find.text('開く'), findsNothing);
  });

  testWidgets('編集、URL除去、原文保持、保存失敗の再試行と通知失敗表示', (tester) async {
    final store = Store();
    final repo = await show(
      tester,
      item(),
      store: store,
      sync: () async => throw StateError('OS'),
    );
    await tester.tap(find.byTooltip('編集'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '新しいタイトル');
    await tester.enterText(find.byType(TextFormField).at(1), 'invalid');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('http または https のURLを入力してください'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), '');
    store.fail = true;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('保存できませんでした。もう一度お試しください'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('新しいタイトル'), findsOneWidget);
    expect(find.text('開く'), findsNothing);
    expect(find.text('変更は保存しました。通知の更新は次回起動時に再試行します'), findsOneWidget);
    expect((await repo.getItem('test'))!.originalText, item().originalText);
  });

  testWidgets('カテゴリ編集は対象通知の文面更新を要求する', (tester) async {
    var synced = 0;
    final repo = await show(
      tester,
      item(text: 'メモ'),
      sync: () async {
        synced++;
      },
    );
    await tester.tap(find.byTooltip('編集'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<ItemCategory>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('読む').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final edited = (await repo.getItem('test'))!;
    expect(edited.category, ItemCategory.read);
    expect(synced, 1);
  });

  for (final throws in [false, true]) {
    testWidgets('外部URLの失敗を表示し保存状態を変えない ($throws)', (tester) async {
      final repo = await show(
        tester,
        item(),
        open: (_) async {
          if (throws) throw StateError('No handler');
          return false;
        },
      );
      final before = (await repo.getItem('test'))!.toJson();
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.text('URLを開けませんでした'), findsOneWidget);
      expect((await repo.getItem('test'))!.toJson(), before);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('削除は確認・取消・失敗を経て保存し通知更新する', (tester) async {
    final store = Store();
    var synced = 0;
    final repo = await show(
      tester,
      item(text: 'メモ'),
      store: store,
      sync: () async {
        synced++;
      },
    );
    await tester.tap(find.byTooltip('削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect((await repo.getItem('test'))!.status, ItemStatus.active);
    store.fail = true;
    await tester.tap(find.byTooltip('削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除する'));
    await tester.pumpAndSettle();
    expect(find.text('削除できませんでした。もう一度お試しください'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.byTooltip('削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除する'));
    await tester.pumpAndSettle();
    expect((await repo.getItem('test'))!.status, ItemStatus.deleted);
    expect(synced, 1);
  });
}
