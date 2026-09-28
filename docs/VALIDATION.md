# 初期構成の検証記録

確認日: 2026-09-27。対象: Phase 1 Issue #1、Flutter 3.47.5 / Dart 3.13.4、Windows 11。

| 対象 | コマンド | 結果 |
| --- | --- | --- |
| Flutter環境 | `flutter --version`, `flutter doctor -v` | stable SDK取得済み。後からAndroid SDK 36.0.0を検出し、ライセンス承諾済み |
| Dart静的解析 | `flutter analyze` | 成功、No issues found |
| Widget test | `flutter test` | 成功、1件通過 |
| Android debug | `flutter build apk --debug` | 成功。英数字パスの一時cloneでAPK生成 |
| Androidエミュレーター | `adb -e install -r`, `adb -e shell am start`, `am force-stop`後の再起動 | Android 16 / API 36のPixel 8エミュレーターで成功。日本語の準備中画面を視認 |
| iOS Simulator build | `flutter build ios --simulator` | 2026-09-28にMacで成功。`build/ios/iphonesimulator/Runner.app`を生成 |
| iOS device build | `flutter build ios --debug --no-codesign` | 2026-09-28にMacで成功。署名と実機へのインストールは未実施 |
| iOS Simulator | `simctl install`、`simctl launch`、`simctl terminate`後の再起動 | iPhone 17 / iOS 27.0で成功。日本語の準備中画面をスクリーンショットで視認 |

作業フォルダとSDKの日本語パスで初回の `flutter analyze` と `flutter test` はFlutter側のパス処理により失敗した。英数字のみの一時ジャンクションから同一ソースとSDKを参照して再実行し、解析とテストは成功した。

Android Studio導入後、`flutter doctor -v` はAndroid SDKと全ライセンスを正常と判定した。ただしジャンクションからのGradleビルドは実パスの非ASCII文字を検出して停止した。英数字パスへコミット `6d88156363ee6e52348bd8119811b1acb9074294` を一時cloneして再実行したところ、Flutter指定のNDK `28.2.13676358` が不足していた。これをAndroid CLIから追加し、debug APKのビルドに成功した。APKは150,368,862バイト、SHA-256は `91DD2D0D19C4048BD8160F34CF8E0CA5A80B7C42CAC0A9BF529E889C69CE0E7C`。一時cloneとAPKはリポジトリ外にあり、コミットしていない。

利用者がPixel 8 / Android 16（API 36）エミュレーターへのAPKインストールで `Success` を確認した。続いてADBで `dev.legionedge.atode_box` を起動し、スクリーンショットで「あとでボックス」「今じゃない。でも忘れたくない。」「入力機能は準備中です」の表示を確認した。`am force-stop` 後の再起動でも同じ画面を確認した。BmaxOSを含むAndroid実機での起動は未検証。

2026-09-28にApple M1 / macOS 26.6.2 / Xcode 27.0のMacでFlutter 3.47.5を使用し、`flutter analyze`（問題なし）、`flutter test`（1件通過）、iOSシミュレーター向けビルド、実機向け署名なしビルドを確認した。iPhone 17 / iOS 27.0シミュレーターでアプリを起動し、「あとでボックス」「今じゃない。でも忘れたくない。」「入力機能は準備中です」の表示を確認した。終了後の再起動にも成功。Mac上の`flutter doctor -v`ではXcodeと端末を検出したが、CocoaPodsは未導入。現時点のプロジェクトにはネイティブiOSプラグインがなく、上記ビルドは成功した。

後続でAndroid実機とiPhone実機での起動を確認する。iPhone実機向けの署名・インストール・起動は未実施。Phase 1の登録・分類・保存・通知は未実装。

環境要件の参照元: [Flutter Androidセットアップ](https://docs.flutter.dev/platform-integration/android/setup)、[Flutter iOSセットアップ](https://docs.flutter.dev/platform-integration/ios/setup)（2026-09-28再確認）。
