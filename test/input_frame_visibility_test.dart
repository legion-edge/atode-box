import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart'
    show MemoryDocumentStore, WidgetTestNotificationPort, testApp;

void main() {
  for (final allowed in [false, true]) {
    for (final scenario in [
      (size: const Size(384, 853.333333), scale: 1.0),
      (size: const Size(240, 480), scale: 2.0),
      (size: const Size(640, 320), scale: 2.0),
    ]) {
      testWidgets(
        'empty frame visibility, refocus and oversized fallback $allowed $scenario',
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
              notificationPort: WidgetTestNotificationPort(allowed: allowed),
            ),
          );
          await tester.pumpAndSettle();
          final field = find.byType(TextField);
          final textField = tester.widget<TextField>(field);
          final controller = textField.controller!;
          final focus = textField.focusNode!;
          final height = tester.getSize(field).height;
          focus.requestFocus();
          await tester.pumpAndSettle();
          void expectVisible() {
            final viewport = tester.getRect(find.byType(SingleChildScrollView));
            final frame = tester.getRect(field);
            expect(frame.height, closeTo(height, 0.001));
            if (height <= viewport.height) {
              expect(frame.top, greaterThanOrEqualTo(viewport.top - 0.001));
              expect(frame.bottom, lessThanOrEqualTo(viewport.bottom + 0.001));
            }
            final editable = tester.state<EditableTextState>(
              find.byType(EditableText),
            );
            final caret = editable.renderEditable.getLocalRectForCaret(
              controller.selection.extent,
            );
            final global = editable.renderEditable.localToGlobal(
              caret.bottomRight,
            );
            expect(global.dy, greaterThanOrEqualTo(viewport.top - 0.001));
            expect(global.dy, lessThanOrEqualTo(viewport.bottom + 0.001));
            expect(controller.text, isEmpty);
            expect(
              tester.widget<TextField>(field).controller,
              same(controller),
            );
            expect(tester.widget<TextField>(field).focusNode, same(focus));
            expect(focus.hasFocus, isTrue);
            expect(tester.takeException(), isNull);
          }

          final insets = scenario.size.height > 800
              ? [358.4, 384.0, 400.0, 384.0, 0.0, 400.0, 0.0]
              : [80.0, scenario.size.height * 0.4, 80.0, 0.0];
          for (final inset in insets) {
            tester.view.viewInsets = FakeViewPadding(bottom: inset);
            tester.view.padding = FakeViewPadding(
              top: 24,
              bottom: inset == 0 ? 48 : 0,
            );
            await tester.pumpAndSettle();
            expectVisible();
            if (inset > 0) {
              focus.unfocus();
              await tester.pumpAndSettle();
              final page = tester.state<ScrollableState>(
                find
                    .ancestor(of: field, matching: find.byType(Scrollable))
                    .first,
              );
              page.position.jumpTo(0);
              await tester.pumpAndSettle();
              focus.requestFocus();
              await tester.pumpAndSettle();
              expectVisible();
              final selection = controller.selection;
              final offset = page.position.pixels;
              focus.unfocus();
              await tester.pumpAndSettle();
              focus.requestFocus();
              await tester.pumpAndSettle();
              expect(controller.selection, selection);
              expect(page.position.pixels, closeTo(offset, 0.001));
              expectVisible();
            }
          }
        },
        variant: TargetPlatformVariant({TargetPlatform.android}),
      );
    }
  }
}
