# 入力欄とキーボードの切替（Issue #37）

確認日: 2026-10-04 JST。起点: main `b19c84f`。

ホームのScaffoldによる即時resizeを止め、キーボードのbottom viewInsetsだけをAnimatedPaddingで120ms・easeOutに補間する。レイアウトの底余白だけを変更し、拡大縮小・位置移動・新規の演出は加えない。MediaQuery.disableAnimationsが有効ならDuration.zeroで直ちに反映する。余白変更終了後のlayoutで、mounted・focus・selectionが有効な入力欄だけ、現在caretをbringIntoViewで再表示する。通知拒否案内、180px以上（文字拡大時は増加）の入力欄、内部と画面全体のスクロール、登録・貼り付け動作を維持する。

IME変化途中の高さを確認するwidget回帰テストは修正前に失敗し、修正後は開閉の途中に中間高さを持つこと、補間終了後の最終高さ、入力・選択位置・focus保持を確認した。動きを減らす設定では最初のframeから最終余白を適用する。320×640・文字倍率2・通知拒否案内で40行入力し、連続inset変更中の入力・selection・focus保持と例外なしを確認した。640×320への回転後、アニメーション収束後の内部scrollと末尾caretのキーボード上の可視性、登録ボタンへの到達と保存再読込を確認した。変化途中の全frameでのcaret可視性を証明した結果ではない。非ゼロのviewPaddingとpaddingでAndroidナビゲーション領域を模した開閉では、caret再表示がない案で長文末尾がIME下に残ることを再現し、上記処理で修正した。通常・動きを減らす設定の双方で安全領域とcaretを確認する。既存の許可／拒否・小画面・文字拡大・回転・長文保存の回帰も成功した。

`flutter analyze`は問題なし、全テスト82件成功。独立read-only再レビューで重大指摘はなく、caret検証のタイミングとナビゲーション余白fixtureを補完した。匿名fixtureの自動検証であり、Samsung IMEの実際の速度・フレーム落ち・動作感の改善を証明した結果ではない。連続inset更新時には補間が再始動するためOS側のキーボードアニメーションより遅れる可能性があり、同期は保証しない。Android/iPhone実機の動作感は本人受入まで未確認とし、Draft PRのmergeを保留する。

端末、導入APK、保存item、通知権限、電池設定、既存10月4日21:00予約を操作していない。通知一覧のフィルター修正、背景通知アクション、通知本文プレビュー、SSD運用規約はこのIssueへ混在させない。追加ローカルAPKビルド・新規Gradleキャッシュは作らず、OSビルドはDraft PRのCIで確認する。

公式資料（2026-10-04 JST確認）: [AnimatedPadding](https://api.flutter.dev/flutter/widgets/AnimatedPadding-class.html)、[ScaffoldのresizeToAvoidBottomInset](https://api.flutter.dev/flutter/material/Scaffold/resizeToAvoidBottomInset.html)、[disableAnimationsOf](https://api.flutter.dev/flutter/widgets/MediaQuery/disableAnimationsOf.html)。
