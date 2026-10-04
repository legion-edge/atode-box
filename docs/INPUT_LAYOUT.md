# 入力欄とキーボードの切替（Issue #37）

最終候補の確認日: 2026-10-04 JST。起点: main `b19c84f`。旧PR39の補間変更だけでは実機の違和感が解消せず、本人承認の固定高さ・初期配置変更へ更新する。

## 最終の挙動

入力欄の高さは `clamp(view高さ × 0.24, 144, 180) × max(1, textScaler.scale(1))`。IME insetから独立した画面寸法を使い、同じ画面寸法・文字倍率でのIME開閉では不変。Galaxy相当の通常文字は180 logical px、低い横画面は144pxを基準とする。回転・画面分割・文字倍率変更時には再計算する。閉じたときに一度に見える量が減る点は本人へ説明して承認された。

残り高さを埋めるExpanded／IntrinsicHeight／ConstrainedBoxを除去する。長文は入力欄内部、小画面や大文字で収まらない操作はページ全体をスクロールする。ページのdragでIMEを閉じる既存仕様は維持する。

通知オフの短い状態表示は入力前に残す。通知許可ボタンと復旧説明は登録・貼り付けの後へ移し、文言とhandlerを維持する。フォーカス連動で案内を隠さない。Galaxy相当384×853.33・通常文字・エラーなしでは入力枠が通知拒否時top215／bottom395pxとなり、IME400pxまで見出し・枠位置とページoffsetが変わらない。

フォーカス獲得とIME余白更新のpost-frameで、枠がviewportに収まるときだけ枠全体を必要量scrollする。既に可視なら動かさない。枠がviewportより大きい場合は固定高さとcaret可視化を優先する。controller・focus・selectionを維持し、focus listenerはdispose時に解除する。

Scaffoldのresizeはfalseで、bottom insetはAndroidで即反映する。iOS通常時の120ms補間とdisableAnimations時の即反映は保持する。追加のscroll時間アニメーションは設けない。

## 検証と本人受入

自動試験は通常Galaxyの連続IME変化でRect／offset不変、5条件の固定高さ、空欄の通知許可／拒否と再フォーカス、IME450／500／600のfallback、狭幅・大文字・横画面・回転、長文末尾、selection・focus保持、caret可視性、登録と貼り付けへの到達、保存再読込を確認する。iOS／動きを減らす設定の補間も別variantで確認する。

製品用の独立準備branchでは `flutter analyze` 指摘なし、`flutter test --no-pub` 全96テスト成功。v7統合候補との差は別PR38の4テストで、入力画面 `lib/main.dart` のファイルSHA256は本人受入済みv7と一致する。最終独立read-onlyレビューにブロッカー・取り込み漏れなし。

PR38を含む統合詳細試験v7（実装 `6c4f526`）は静的解析と100テスト成功、profile arm64 APKをビルド済み。Galaxy A25 5Gで本人が通常サイズについて以下を確認した。

- 空欄タップとIME開閉で見出し／画面全体が上へずれない。
- 入力枠下辺がIMEに隠れない。
- 長文を欄内で末尾までスクロールできる。
- IME再開後に文字とカーソル位置が保持される。
- IMEを閉じた後に「貼り付けて追加」が見える。

選択範囲保持、大文字・横画面・高いIMEは自動試験の結果で、実機本人受入とは区別する。IMEを開いたまま貼り付けボタンへ到達すること、本人による試験文保存成功は確認していない。「貼り付けて追加」は非空入力でも表示され、clipboard内容を直接保存する操作であり、今回押していない。

更新時に空欄を確認し、両アプリの保存データ・通知権限・予約ファイルは前後一致、元試験アプリ4件と10月4日21時JST予約・OS alarmを保持した。現在の未保存試験文は本人が保持中で、更新・終了・破棄・保存を行わない。実機の履歴と各候補の限界は [FIXED_INPUT_TRIAL.md](FIXED_INPUT_TRIAL.md) に記録する。

## PRの境界

製品差分に試験専用package／label、診断buffer／VM extension、PR38のfilter変更、PR41の背景処理を含めない。PR38は独立したPRで保持し、最終統合候補ではその位置安定化と合わせて試験した。保存schema・repository・通知処理・依存・権限設定を変更しない。

製品用branchを検証し、新HEADのCIはpush後に確認する。旧HEAD `0089a1c` のCI4ジョブ成功を新HEADの結果として扱わない。mergeは未許可。
