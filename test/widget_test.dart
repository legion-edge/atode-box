import 'dart:io';

import 'package:atode_box/main.dart';
import 'package:atode_box/classification/category_presentation.dart';
import 'package:atode_box/storage/inbox_item.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/notifications/notification_port.dart';
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

class WidgetTestNotificationPort implements NotificationPort {
  WidgetTestNotificationPort({this.allowed = true});

  bool allowed;
  final requests = <int, LocalNotice>{};
  @override
  Future<void> initialize(void Function(NoticeResponse) onResponse) async {}
  @override
  Future<NoticeResponse?> launchResponse() async => null;
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
  Future<void> schedule(LocalNotice notice) async =>
      requests[notice.id] = notice;
  @override
  Future<void> cancel(int id) async => requests.remove(id);
}

AtodeBoxApp testApp(
  LocalRepository repository, {
  NotificationPort? notificationPort,
}) => AtodeBoxApp(
  repository: repository,
  notificationPort: notificationPort ?? WidgetTestNotificationPort(),
);

void main() {
  Future<void> pumpReady(
    WidgetTester tester,
    LocalRepository repository,
  ) async {
    await repository.saveSettings(
      const LifestyleSettings(initialSetupComplete: true),
    );
    await tester.pumpWidget(testApp(repository));
    await tester.pumpAndSettle();
  }

  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('IMEの出入りで入力欄を短く補間し、入力と選択を保つ', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final repo = LocalRepository(MemoryDocumentStore());
    await pumpReady(tester, repo);
    final field = find.byType(TextField);
    await tester.enterText(field, '変化中も入力を保つ\n2行目');
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 3);
    final closedHeight = tester.getSize(field).height;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final duringOpen = tester.getSize(field).height;
    await tester.pumpAndSettle();
    final openHeight = tester.getSize(field).height;
    expect(duringOpen, greaterThan(openHeight));
    expect(duringOpen, lessThan(closedHeight));
    expect(tester.getRect(find.text('登録')).bottom, lessThanOrEqualTo(520));
    expect(controller.text, '変化中も入力を保つ\n2行目');
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final duringClose = tester.getSize(field).height;
    expect(duringClose, greaterThan(openHeight));
    expect(duringClose, lessThan(closedHeight));
    await tester.pumpAndSettle();
    expect(tester.getSize(field).height, closedHeight);
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('動きを減らす設定ではIME余白を補間せず適用する', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final repo = LocalRepository(MemoryDocumentStore());
    await pumpReady(tester, repo);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();
    final firstHeight = tester.getSize(find.byType(TextField)).height;
    expect(tester.getRect(find.text('登録')).bottom, lessThanOrEqualTo(520));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getSize(find.byType(TextField)).height, firstHeight);
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets('ナビゲーション余白とIME開閉でも安全領域とcaretを保つ ($reducedMotion)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reducedMotion);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final repo = LocalRepository(MemoryDocumentStore());
      await pumpReady(tester, repo);
      final field = find.byType(TextField);
      await tester.enterText(field, List.filled(20, '匿名の入力').join('\n'));
      await tester.pumpAndSettle();
      final closedHeight = tester.getSize(field).height;
      for (final keyboardOpen in [true, false]) {
        tester.view.viewInsets = FakeViewPadding(
          bottom: keyboardOpen ? 280 : 0,
        );
        tester.view.padding = FakeViewPadding(
          top: 24,
          bottom: keyboardOpen ? 0 : 24,
        );
        await tester.pumpAndSettle();
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        final caret = editable.renderEditable.getLocalRectForCaret(
          editable.widget.controller.selection.extent,
        );
        final global = editable.renderEditable.localToGlobal(caret.bottomRight);
        expect(global.dy, lessThanOrEqualTo(keyboardOpen ? 520 : 776));
        expect(global.dy, greaterThan(80));
        expect(
          tester.getRect(find.text('登録')).bottom,
          lessThanOrEqualTo(keyboardOpen ? 520 : 776),
        );
        expect(tester.takeException(), isNull);
      }
      expect(tester.getSize(field).height, closedHeight);
    });
  }

  testWidgets('長文入力中のIME連続変化・回転でcaretとscrollと保存を保つ', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final store = MemoryDocumentStore();
    final repo = LocalRepository(store);
    await repo.saveSettings(
      const LifestyleSettings(initialSetupComplete: true),
    );
    await tester.pumpWidget(
      testApp(
        repo,
        notificationPort: WidgetTestNotificationPort(allowed: false),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    final input = List.generate(40, (index) => '匿名の長文 $index').join('\n');
    await tester.enterText(field, input);
    final controller = tester.widget<TextField>(field).controller!;
    final selection = TextSelection.collapsed(offset: input.length);
    controller.selection = selection;
    for (final inset in [80.0, 160.0, 280.0, 160.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.takeException(), isNull);
      expect(controller.text, input);
      expect(controller.selection, selection);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    }
    tester.view.physicalSize = const Size(640, 320);
    tester.view.viewInsets = const FakeViewPadding(bottom: 120);
    await tester.pumpAndSettle();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.renderEditable.offset.pixels, greaterThan(0));
    final caret = editable.renderEditable.getLocalRectForCaret(
      selection.extent,
    );
    expect(caret.top, greaterThanOrEqualTo(0));
    expect(
      caret.bottom,
      lessThanOrEqualTo(editable.renderEditable.size.height),
    );
    expect(
      editable.renderEditable.localToGlobal(caret.bottomRight).dy,
      lessThanOrEqualTo(200),
    );
    await tester.ensureVisible(find.text('登録'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(
      (await LocalRepository(store).allItems()).single.originalText,
      input,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('拒否案内とキーボードでも入力欄の文字を表示できる高さを保つ', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final repository = LocalRepository(MemoryDocumentStore());
    await repository.saveSettings(
      const LifestyleSettings(initialSetupComplete: true),
    );
    await tester.pumpWidget(
      testApp(
        repository,
        notificationPort: WidgetTestNotificationPort(allowed: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(TextField)).height,
      greaterThanOrEqualTo(180),
    );
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '入力を読める\n複数行');
    await tester.pumpAndSettle();
    expect(find.text('入力を読める\n複数行'), findsOneWidget);
  });

  for (final allowed in [false, true]) {
    testWidgets('小画面・大文字・回転・キーボード閉じても長文を保ち登録できる ($allowed)', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = MemoryDocumentStore();
      final repository = LocalRepository(store);
      await repository.saveSettings(
        const LifestyleSettings(initialSetupComplete: true),
      );
      await tester.pumpWidget(
        testApp(
          repository,
          notificationPort: WidgetTestNotificationPort(allowed: allowed),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(192),
      );
      await tester.ensureVisible(find.byType(TextField));
      final input = List.generate(40, (index) => '記事の長文 $index').join('\n');
      await tester.enterText(find.byType(TextField), input);
      await tester.pumpAndSettle();
      // Dismiss the simulated IME, then rotate and show it again.
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        input,
      );
      tester.view.physicalSize = const Size(800, 360);
      tester.view.viewInsets = const FakeViewPadding(bottom: 120);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        input,
      );
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      expect(
        scroll.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      await tester.ensureVisible(find.text('登録'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登録'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        (await LocalRepository(store).allItems()).single.originalText,
        input,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    });
  }

  testWidgets('初回は既定値を案内し、保存後の2回目は表示しない', (tester) async {
    final store = MemoryDocumentStore();
    await tester.pumpWidget(testApp(LocalRepository(store)));
    await tester.pumpAndSettle();
    expect(find.text('このまま使う'), findsOneWidget);
    expect(find.textContaining('18:00'), findsOneWidget);
    expect(find.textContaining('19:00'), findsOneWidget);
    expect(find.textContaining('土日・日本の祝日'), findsOneWidget);
    await tester.tap(find.text('このまま使う'));
    await tester.pumpAndSettle();
    expect(find.text('あとで見たいこと'), findsOneWidget);
    expect(
      (await LocalRepository(store).getSettings()).initialSetupComplete,
      isTrue,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(testApp(LocalRepository(store)));
    await tester.pumpAndSettle();
    expect(find.text('このまま使う'), findsNothing);
    expect(find.text('あとで見たいこと'), findsOneWidget);
  });

  testWidgets('設定画面で時刻と休日を変更して保存できる', (tester) async {
    final store = MemoryDocumentStore();
    await tester.pumpWidget(testApp(LocalRepository(store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('設定を変更する'));
    await tester.pumpAndSettle();
    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('19:00'), findsOneWidget);
    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '17');
    await tester.enterText(find.byType(TextField).last, '30');
    await tester.tap(find.text('決定'));
    await tester.pumpAndSettle();
    expect(find.text('17:30'), findsOneWidget);
    await tester.tap(find.text('土日を休日にする'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();
    final saved = await LocalRepository(store).getSettings();
    expect(saved.commuteStartMinute, 17 * 60 + 30);
    expect(saved.weekendsAreHolidays, isFalse);
    expect(saved.initialSetupComplete, isTrue);
    expect(find.text('あとで見たいこと'), findsOneWidget);
  });

  testWidgets('初回設定の保存失敗は案内を完了しない', (tester) async {
    final store = MemoryDocumentStore()..failWrite = true;
    await tester.pumpWidget(testApp(LocalRepository(store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('このまま使う'));
    await tester.pumpAndSettle();
    expect(find.text('このまま使う'), findsOneWidget);
    expect(find.textContaining('保存できませんでした'), findsOneWidget);
    expect(store.contents, isNull);
  });

  testWidgets('設定画面の保存失敗は画面に残して再試行できる', (tester) async {
    final store = MemoryDocumentStore();
    final repository = LocalRepository(store);
    await pumpReady(tester, repository);
    await tester.tap(find.byTooltip('設定'));
    await tester.pumpAndSettle();
    store.failWrite = true;
    await tester.tap(find.text('土日を休日にする'));
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();
    expect(find.text('生活時間の設定'), findsOneWidget);
    expect(find.textContaining('保存できませんでした'), findsOneWidget);
    expect(
      (await LocalRepository(store).getSettings()).weekendsAreHolidays,
      isTrue,
    );
    store.failWrite = false;
    await tester.tap(find.text('保存する'));
    await tester.pumpAndSettle();
    expect(
      (await LocalRepository(store).getSettings()).weekendsAreHolidays,
      isFalse,
    );
  });

  testWidgets('入力を保存し、確認表示の後も連続で登録できる', (tester) async {
    final store = MemoryDocumentStore();
    final repository = LocalRepository(store);
    await pumpReady(tester, repository);

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
    expect(items.last.nextNotifyAt, isNotNull);
    expect(items.last.nextNotifyAt!.isAfter(items.last.savedAt), isTrue);
    expect(items.last.context, 'next_day_evening');
    expect(items.last.category, ItemCategory.memo);
  });

  testWidgets('ホームから通知一覧へ移動し、保存項目を確認できる', (tester) async {
    final repository = LocalRepository(MemoryDocumentStore());
    await pumpReady(tester, repository);
    await tester.enterText(find.byType(TextField), '一覧で確認するメモ');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('通知一覧'));
    await tester.pumpAndSettle();
    expect(find.text('通知一覧'), findsOneWidget);
    await tester.tap(find.text('明日以降'));
    await tester.pumpAndSettle();
    expect(find.text('一覧で確認するメモ'), findsOneWidget);
  });

  testWidgets('通知を拒否しても保存でき、端末設定からの復旧方法が見える', (tester) async {
    final repository = LocalRepository(MemoryDocumentStore());
    await repository.saveSettings(
      const LifestyleSettings(initialSetupComplete: true),
    );
    await tester.pumpWidget(
      testApp(
        repository,
        notificationPort: WidgetTestNotificationPort(allowed: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('通知を許可する'), findsOneWidget);
    expect(find.textContaining('端末の設定で'), findsOneWidget);
    await tester.tap(find.text('通知を許可する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('端末の設定で'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '拒否中のメモ');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect((await repository.allItems()).single.originalText, '拒否中のメモ');
  });

  testWidgets('空欄と空白だけの入力は保存しない', (tester) async {
    final repository = LocalRepository(MemoryDocumentStore());
    await pumpReady(tester, repository);
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
    await pumpReady(tester, repository);
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
    await pumpReady(tester, repository);
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
    await pumpReady(tester, repository);
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
    final store = MemoryDocumentStore();
    await LocalRepository(store)
        .saveSettings(const LifestyleSettings(initialSetupComplete: true));
    store.failWrite = true;
    await tester.pumpWidget(testApp(LocalRepository(store)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '消さないメモ');
    await tester.tap(find.text('登録'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '消さないメモ',
    );
    expect(find.text('登録しました'), findsNothing);
    expect((await LocalRepository(store).allItems()), isEmpty);
  });
}
