import 'dart:io';

import 'package:atode_box/main.dart';
import 'package:atode_box/classification/category_presentation.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryDocumentStore implements DocumentStore {
  String? contents;
  bool failWrite = false;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async {
    if (failWrite) throw const FileSystemException('write failed');
    this.contents = contents;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('入力を保存し、確認表示の後も連続で登録できる', (tester) async {
    final store = MemoryDocumentStore();
    final repository = LocalRepository(store);
    await tester.pumpWidget(AtodeBoxApp(repository: repository));

    expect(find.text('あとで見たいこと'), findsOneWidget);
    expect(find.text('貼り付けて追加'), findsOneWidget);
    expect(find.byTooltip('通知一覧'), findsOneWidget);
    expect(find.byTooltip('設定'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  気になる場所  ');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(find.text('登録しました'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect((await repository.allItems()).single.originalText, '  気になる場所  ');

    await tester.enterText(find.byType(TextField), '次のメモ');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    final items = await repository.allItems();
    expect(items, hasLength(2));
    expect(items.last.originalText, '次のメモ');
    expect(items.last.needsProcessing, isTrue);
    expect(items.last.nextNotifyAt, isNull);
    expect(items.last.category, ItemCategory.memo);
  });

  testWidgets('空欄と空白だけの入力は保存しない', (tester) async {
    final repository = LocalRepository(MemoryDocumentStore());
    await tester.pumpWidget(AtodeBoxApp(repository: repository));
    await tester.tap(find.text('登録'));
    await tester.enterText(find.byType(TextField), '  \n ');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(await repository.allItems(), isEmpty);
    expect(find.text('登録しました'), findsNothing);
  });

  testWidgets('キーボード表示中も登録ボタンに届く', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    final repository = LocalRepository(MemoryDocumentStore());
    await tester.pumpWidget(AtodeBoxApp(repository: repository));
    await tester.enterText(find.byType(TextField), 'キーボード中の入力');
    await tester.pump();
    expect(tester.getRect(find.text('登録')).bottom, lessThan(480));
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect((await repository.allItems()).single.originalText, 'キーボード中の入力');
  });

  testWidgets('クリップボードは明示操作でだけ読み、空なら保存しない', (tester) async {
    var reads = 0;
    String? clipboardText;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        reads++;
        return clipboardText == null ? null : {'text': clipboardText};
      }
      return null;
    });
    final repository = LocalRepository(MemoryDocumentStore());
    await tester.pumpWidget(AtodeBoxApp(repository: repository));
    expect(reads, 0);

    await tester.tap(find.text('貼り付けて追加'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(await repository.allItems(), isEmpty);

    clipboardText = '  ';
    await tester.tap(find.text('貼り付けて追加'));
    await tester.pumpAndSettle();
    expect(await repository.allItems(), isEmpty);

    clipboardText = 'https://example.com/';
    await tester.tap(find.text('貼り付けて追加'));
    await tester.pumpAndSettle();
    expect(reads, 3);
    expect((await repository.allItems()).single.originalText, clipboardText);
    expect((await repository.allItems()).single.category, ItemCategory.memo);
    expect(find.text('登録しました'), findsOneWidget);
  });

  testWidgets('分類結果を文字・アイコン・色で表示し、入力時の選択は不要', (tester) async {
    final repository = LocalRepository(MemoryDocumentStore());
    await tester.pumpWidget(AtodeBoxApp(repository: repository));
    expect(find.byType(DropdownButton<ItemCategory>), findsNothing);
    await tester.enterText(find.byType(TextField), '京都に行きたい');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect((await repository.allItems()).single.category, ItemCategory.go);
    expect((await repository.allItems()).single.needsProcessing, isTrue);
    expect(find.text('行く'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(ItemCategory.go.icon));
    expect(icon.color, ItemCategory.go.color);
    expect(find.byType(CategoryBadge), findsOneWidget);
  });

  testWidgets('7カテゴリそれぞれに日本語名・アイコン・色がある', (tester) async {
    const labels = <ItemCategory, String>{
      ItemCategory.read: '読む',
      ItemCategory.watch: '見る',
      ItemCategory.go: '行く',
      ItemCategory.buy: '買う',
      ItemCategory.doTask: 'やる',
      ItemCategory.idea: 'アイデア',
      ItemCategory.memo: 'メモ',
    };
    for (final entry in labels.entries) {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: CategoryBadge(entry.key))),
      );
      expect(find.text(entry.value), findsOneWidget);
      expect(find.byIcon(entry.key.icon), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(entry.key.icon));
      expect(icon.color, entry.key.color);
    }
  });

  testWidgets('保存失敗時は入力を残し、成功表示を出さない', (tester) async {
    final store = MemoryDocumentStore()..failWrite = true;
    await tester.pumpWidget(AtodeBoxApp(repository: LocalRepository(store)));
    await tester.enterText(find.byType(TextField), '消さないメモ');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '消さないメモ',
    );
    expect(find.text('登録しました'), findsNothing);
    expect(store.contents, isNull);
  });
}
