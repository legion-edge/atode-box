# 入力欄とキーボードの切替（Issue #37）

確認日: 2026-10-04 JST。起点: main `b19c84f`。

## 現在の候補

Androidでは、OSから届くbottom viewInsetsに追加の時間補間を行わない。既存AnimatedPaddingのdurationをDuration.zeroにして、そのlayoutで直ちに反映する。iOS通常時の120ms・easeOutと、disableAnimations有効時の即時反映は保持する。ScaffoldのresizeToAvoidBottomInsetはfalseなので、同じinsetを2回加算しない。

同じwrapperのonEndを残し、余白変更後のlayoutでmounted・focus・selectionが有効な入力欄だけ現在caretをbringIntoViewで再表示する。zero-durationでもこの補正は維持する。通知拒否案内、180px以上（文字拡大時は増加）の入力欄、内部と画面全体のscroll、入力・選択・focus、登録・貼り付け動作を保つ。

## 検証結果

Androidの開閉時は最初のlayoutで最終高さになり、40ms後・settle後に追加の高さ変化がないことを確認した。この新assertは旧120ms版で493pxと213pxが一致せず失敗し、直接反映候補で成功した。iOS通常時の中間高さと、disableAnimations時の即時反映も別variantで検証した。

320×640・文字倍率2・通知拒否案内で40行入力し、連続inset更新（80/160/280/160/0）ごとに最初のframeでSafeArea下端が640-insetに一致し、40ms後に余計な追従変化がないことを確認した。入力・selection・focus、回転後のscrollと末尾caret、登録ボタンへの到達と保存再読込を検証した。非ゼロのviewPadding/paddingで安全領域とcaretも確認する。変化途中の全frameでのcaret可視性を証明した結果ではない。

flutter analyze指摘なし、全83テスト成功。独立read-onlyレビューで重大指摘なし。保存schema・repository・通知処理・依存・権限設定は変更していない。

## 本人結果と動画所見の範囲

旧候補 `2ead932`／versionCode 2では、本人が「枠の拡大、縮小の変化をあまり感じない」、さらに「IMEがせり上がる速度よりフォーム縮小が遅い」と報告し、主観改善は未受入。

親が30fps外部撮影動画を直接確認し、2回のopeningでIMEが下部controlsへ重なる間は枠が高く、その後短縮した枠境界が見えると報告した。子担当は動画を直接閲覧していない。重なりによって底辺が隠れるため正確なlag msや120ms補間が原因とは確定していない。closingは通知permission dialogで遮蔽され、純粋な閉じ試験とは扱わない。5〜6行入力・末尾視認・scrollも本人の明示結果待ち。

新候補はアプリ側の追加遅延を取り除く対策であり、OSがinsetを一括更新する場合の段階移動、実IMEとの開始／終了同期、debug buildのframe落ちまで解消したと主張しない。Samsung IMEの体感は次の本人受入まで未確認。Draftを維持してmergeを保留する。

## 今回の境界

本修正段階ではnativebuild・APK更新・端末操作・アニメーション設定変更を行っていない。親から最終結果報告後のnative候補準備指示があるまで、追加nativebuildを待つ。PRの自動OSビルドもHEADの[skip ci]で抑止し、CI成功とは報告しない。旧HEADのCI成功は旧候補の記録とする。

PR38のフィルター位置ずれ解消は本人確認済みで別件。新候補へ合わせる際にも維持する。PR41背景処理、通知preview、SSD運用は含めない。元通知試験アプリの4件と10月4日21:00予約・既存詳細試験データを保持する。

公式資料（同日確認）: [AnimatedPadding](https://api.flutter.dev/flutter/widgets/AnimatedPadding-class.html)、[Scaffold resize](https://api.flutter.dev/flutter/material/Scaffold/resizeToAvoidBottomInset.html)、[disableAnimationsOf](https://api.flutter.dev/flutter/widgets/MediaQuery/disableAnimationsOf.html)、[GitHub workflow skip](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs)。
