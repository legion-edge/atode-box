import 'package:atode_box/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('初期画面は未実装の機能を利用可能と表示しない', (tester) async {
    await tester.pumpWidget(const AtodeBoxApp());

    expect(find.text('あとでボックス'), findsOneWidget);
    expect(find.text('入力機能は準備中です'), findsOneWidget);
    expect(find.text('登録が完了したよ！'), findsNothing);
  });
}
