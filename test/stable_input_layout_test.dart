import 'package:atode_box/storage/lifestyle_settings.dart';
import 'package:atode_box/storage/local_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart'
    show MemoryDocumentStore, WidgetTestNotificationPort, testApp;

class CountingPermissionPort extends WidgetTestNotificationPort {
  CountingPermissionPort({required super.allowed});
  int permissionRequests = 0;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return allowed;
  }
}

void main() {
  for (final allowed in [false, true]) {
    testWidgets(
      'Galaxy heading and input remain still through normal IME $allowed',
      (tester) async {
        tester.view.physicalSize = const Size(384, 853.333333);
        tester.view.devicePixelRatio = 1;
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 48);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewPadding);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewInsets);
        final repo = LocalRepository(MemoryDocumentStore());
        await repo.saveSettings(
          const LifestyleSettings(initialSetupComplete: true),
        );
        final port = CountingPermissionPort(allowed: allowed);
        await tester.pumpWidget(testApp(repo, notificationPort: port));
        await tester.pumpAndSettle();
        final field = find.byType(TextField);
        final heading = find.text('今じゃない。でも忘れたくない。');
        final initialFrame = tester.getRect(field);
        final initialHeading = tester.getRect(heading);
        final controller = tester.widget<TextField>(field).controller!;
        final focus = tester.widget<TextField>(field).focusNode!;
        final page = tester.state<ScrollableState>(
          find.ancestor(of: field, matching: find.byType(Scrollable)).first,
        );
        expect(initialFrame.height, 180);
        expect(initialFrame.top, allowed ? 187 : 215);
        expect(page.position.pixels, 0);
        if (!allowed) {
          expect(
            tester.getRect(find.text('通知はオフです。保存はそのまま使えます。')).bottom,
            lessThan(initialFrame.top),
          );
          expect(
            tester.getRect(find.text('通知を許可する')).top,
            greaterThan(tester.getRect(find.text('貼り付けて追加')).bottom),
          );
        }
        await tester.tap(field);
        await tester.pumpAndSettle();
        final selection = controller.selection;
        for (final inset in [
          0.0,
          16.0,
          80.0,
          160.0,
          280.0,
          358.4,
          400.0,
          358.4,
          160.0,
          0.0,
        ]) {
          tester.view.viewInsets = FakeViewPadding(bottom: inset);
          tester.view.padding = FakeViewPadding(
            top: 24,
            bottom: inset == 0 ? 48 : 0,
          );
          await tester.pumpAndSettle();
          expect(tester.getRect(field), initialFrame);
          expect(tester.getRect(heading), initialHeading);
          expect(page.position.pixels, 0);
          expect(
            tester.getRect(field).bottom,
            lessThanOrEqualTo(
              tester.getRect(find.byType(SingleChildScrollView)).bottom,
            ),
          );
          expect(controller.text, isEmpty);
          expect(controller.selection, selection);
          expect(focus.hasFocus, isTrue);
          expect(port.permissionRequests, 0);
          expect(tester.takeException(), isNull);
          if (!allowed) {
            expect(find.text('通知を許可する'), findsOneWidget);
            expect(find.textContaining('一度拒否した場合'), findsOneWidget);
          }
        }
        if (!allowed) {
          await tester.ensureVisible(find.text('通知を許可する'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('通知を許可する'));
          await tester.pumpAndSettle();
          expect(port.permissionRequests, 1);
          expect(find.textContaining('一度拒否した場合'), findsOneWidget);
        }
      },
      variant: TargetPlatformVariant({TargetPlatform.android}),
    );
  }
}
