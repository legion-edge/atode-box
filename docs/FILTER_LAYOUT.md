# 通知一覧フィルターの配置（Issue #36）

確認日: 2026-10-04 JST。起点: main `b19c84f`。

通知一覧は同じ順序のChoiceChipをWrapで配置する。選択チェックは18pxのアイコン領域を常に確保し、未選択時は透明にする。自動チェックは二重表示を避けて無効にし、ChoiceChipのselectedと選択色・チェック表示を保つ。アイコンの読み上げは除外して、選択状態はChoiceChipの意味情報で伝える。

同じ幅・文字倍率なら、どのフィルターを選んでも各chipの位置と大きさが変わらない。段数は固定せず、狭い画面や文字拡大時は必要な折返しを許す。単一の固定px幅や固定3＋2段は使わない。

修正前のwidget回帰テストは360×800・倍率1、320×640・240×800・640×320・倍率2の4条件すべてで、選択変更による幅・位置変化を再現した。修正後は同条件で全5フィルターの位置・サイズ・選択状態・タップ可能性と例外なしを確認した。`flutter analyze`は問題なし、`flutter test`は81件成功。独立read-onlyレビューで重大指摘はなく、追加した意味情報のラベル・selected状態のテストも一覧9件すべて成功した。fixtureは匿名で、個人画像や保存データは使っていない。

Android/iOSの修正版実機表示は未確認。既存の「完了済み選択時に段位置が移る」は本人報告で、今回の根拠はコードとwidget再現である。端末・APK・通知権限・OS予約を変更していない。ローカルAndroid追加ビルドと新規Gradleキャッシュは作らず、OSビルドはDraft PRのCIで確認する。実機の見た目の受入後までmergeを保留する。

公式資料（2026-10-04 JST確認）: [ChoiceChipのチェック表示](https://api.flutter.dev/flutter/material/ChoiceChip/showCheckmark.html)、[avatar](https://api.flutter.dev/flutter/material/ChoiceChip/avatar.html)、[Wrapの折返し](https://api.flutter.dev/flutter/widgets/Wrap-class.html)。
