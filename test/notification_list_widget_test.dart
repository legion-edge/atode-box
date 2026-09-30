import 'dart:convert';

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

  testWidgets('開いたまま現地0時を越えるとフィルターを再判定する', (tester) async {
    var clock = DateTime.utc(2026, 9, 30, 14, 59); // 23:59 in UTC+9
    final repository = LocalRepository(MemoryStore());
    await repository.saveItem(
      InboxItem(
        id: 'midnight',
        originalText: '日付をまたぐメモ',
        savedAt: clock,
        nextNotifyAt: DateTime.utc(2026, 9, 30, 15, 30),
      ),
    );
    await repository.saveItem(
      InboxItem(
        id: 'week-edge',
        originalText: '週の境界にあるメモ',
        savedAt: clock,
        nextNotifyAt: DateTime.utc(2026, 10, 7, 3),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: NotificationListScreen(
          repository: repository,
          settings: settings,
          now: () => clock,
          zone: zone,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('明日以降'));
    await tester.pumpAndSettle();
    expect(find.text('日付をまたぐメモ'), findsOneWidget);
    await tester.tap(find.text('1週間後以降'));
    await tester.pumpAndSettle();
    expect(find.text('週の境界にあるメモ'), findsOneWidget);

    clock = DateTime.utc(2026, 9, 30, 15); // local midnight
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(find.text('1週間後以降の予定はありません'), findsOneWidget);
    await tester.tap(find.text('明日以降'));
    await tester.pumpAndSettle();
    expect(find.text('日付をまたぐメモ'), findsNothing);
    expect(find.text('週の境界にあるメモ'), findsOneWidget);
    await tester.tap(find.text('今日'));
    await tester.pumpAndSettle();
    expect(find.text('日付をまたぐメモ'), findsOneWidget);
  });

  testWidgets('旧スキーマの未予定activeを今日に表示し、内容も開ける', (tester) async {
    final store = MemoryStore()
      ..contents = jsonEncode({
        'items': [
          {
            'id': 'legacy',
            'original_text': '以前に保存したメモ',
            'saved_at': '2026-09-01T12:00:00.000Z',
            'status': 'active',
          },
        ],
        'settings': {'initial_setup_complete': true},
      });
    await tester.pumpWidget(app(LocalRepository(store)));
    await tester.pumpAndSettle();
    expect(find.text('以前に保存したメモ'), findsOneWidget);
    expect(find.text('次回未設定'), findsOneWidget);
    await tester.tap(find.byType(Card));
    await tester.pumpAndSettle();
    expect(find.text('保存した内容'), findsOneWidget);
    expect(find.text('次回未設定'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
