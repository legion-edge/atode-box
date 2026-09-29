import 'package:atode_box/notification_list/notification_list_screen.dart';
import 'package:atode_box/scheduling/schedule_engine.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryStore implements DocumentStore {
  String? contents;
  @override
  Future<String?> read() async => contents;
  @override
  Future<void> write(String value) async => contents = value;
}

void main() {
  final now = DateTime.utc(2026, 9, 30, 14, 30);
  const zone = FixedOffsetZone(Duration(hours: 9));
  const settings = LifestyleSettings();

  Widget app(LocalRepository repository) => MaterialApp(
    theme: ThemeData(splashFactory: InkRipple.splashFactory),
    home: NotificationListScreen(
      repository: repository,
      settings: settings,
      now: () => now,
      zone: zone,
    ),
  );

  testWidgets('空状態と全フィルターを表示する', (tester) async {
    await tester.pumpWidget(app(LocalRepository(MemoryStore())));
    await tester.pumpAndSettle();
    expect(find.text('今日の予定はありません'), findsOneWidget);
    for (final label in ['今日', '明日以降', '休日', '1週間後以降', '完了済み']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('完了済み'));
    await tester.pumpAndSettle();
    expect(find.text('完了済みの項目はありません'), findsOneWidget);
  });

  testWidgets('長文と狭い画面で表示が崩れず、内容へ進める', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = LocalRepository(MemoryStore());
    final longText = '長い内容を確認する。' * 80;
    await repository.saveItem(
      InboxItem(
        id: 'long',
        originalText: longText,
        savedAt: now,
        category: ItemCategory.read,
        nextNotifyAt: DateTime.utc(2026, 9, 30, 14, 59),
      ),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final summary = find.byType(Card);
    expect(summary, findsOneWidget);
    expect(find.text('読む'), findsOneWidget);
    expect(find.textContaining('次回 2026年9月30日 23:59'), findsOneWidget);
    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(find.text('保存した内容'), findsOneWidget);
    expect(find.text(longText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存済み項目をフィルターで切り替える', (tester) async {
    final repository = LocalRepository(MemoryStore());
    await repository.saveItem(
      InboxItem(
        id: 'later',
        originalText: '明日のメモ',
        savedAt: now,
        nextNotifyAt: DateTime.utc(2026, 10, 1, 12),
      ),
    );
    await tester.pumpWidget(app(repository));
    await tester.pumpAndSettle();
    expect(find.text('今日の予定はありません'), findsOneWidget);
    await tester.tap(find.text('明日以降'));
    await tester.pumpAndSettle();
    expect(find.text('明日のメモ'), findsOneWidget);
  });
}
