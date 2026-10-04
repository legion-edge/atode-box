import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart'
    show MemoryDocumentStore, WidgetTestNotificationPort, testApp;

void main() {
  for (final scenario in [
    (size: const Size(384, 853.333333), scale: 1.0, height: 180.0),
    (size: const Size(320, 640), scale: 2.0, height: 307.2),
    (size: const Size(240, 480), scale: 2.0, height: 288.0),
    (size: const Size(640, 320), scale: 1.0, height: 144.0),
    (size: const Size(360, 800), scale: 3.0, height: 540.0),
  ]) {
    testWidgets(
      'fixed input survives IME, long text and reachable actions $scenario',
      (tester) async {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
        tester.platformDispatcher.textScaleFactorTestValue = scenario.scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
        final field = find.byType(TextField);
        final text = List.generate(40, (i) => '長文入力を保持 $i').join('\n');
        await tester.ensureVisible(field);
        await tester.enterText(field, text);
        final widget = tester.widget<TextField>(field);
        final controller = widget.controller!;
        final focus = widget.focusNode!;
        final selection = TextSelection.collapsed(offset: text.length);
        controller.selection = selection;
        for (final inset in [
          0.0,
          80.0,
          scenario.size.height * 0.4,
          80.0,
          0.0,
        ]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          tester.view.padding = FakeViewPadding(
            top: 24,
            bottom: inset == 0 ? 48 : 0,
          );
          await tester.pumpAndSettle();
          expect(tester.getSize(field).height, closeTo(scenario.height, 0.001));
          expect(tester.widget<TextField>(field).controller, same(controller));
          expect(tester.widget<TextField>(field).focusNode, same(focus));
          expect(controller.text, text);
          expect(controller.selection, selection);
          expect(focus.hasFocus, isTrue);
          final editable = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          expect(editable.renderEditable.offset.pixels, greaterThan(0));
          final caret = editable.renderEditable.getLocalRectForCaret(
            selection.extent,
          );
          final globalBottom = editable.renderEditable
              .localToGlobal(caret.bottomRight)
              .dy;
          expect(
            globalBottom,
            lessThanOrEqualTo(
              scenario.size.height - inset - (inset == 0 ? 48 : 0) + 0.001,
            ),
          );
          expect(globalBottom, greaterThan(80));
          expect(tester.takeException(), isNull);
          for (final label in ['登録', '貼り付けて追加']) {
            await tester.ensureVisible(find.text(label));
            await tester.pumpAndSettle();
            expect(find.text(label).hitTestable(), findsOneWidget);
            expect(
              tester.getRect(find.text(label)).bottom,
              lessThanOrEqualTo(
                scenario.size.height - inset - (inset == 0 ? 48 : 0) + 0.001,
              ),
            );
            expect(tester.takeException(), isNull);
          }
        }
        controller.selection = const TextSelection(
          baseOffset: 2,
          extentOffset: 8,
        );
        tester.view.viewInsets = FakeViewPadding(
          bottom: scenario.size.height * 0.4,
        );
        await tester.pumpAndSettle();
        expect(
          controller.selection,
          const TextSelection(baseOffset: 2, extentOffset: 8),
        );
      },
      variant: TargetPlatformVariant({TargetPlatform.android}),
    );
  }
}
