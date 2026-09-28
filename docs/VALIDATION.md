# 初期構成の検証記録

確認日: 2026-09-27〜28。対象: Phase 1 Issue #1、Flutter 3.47.5 / Dart 3.13.4、Windows 11 / macOS 26.6.2。

| 対象 | コマンド | 結果 |
| --- | --- | --- |
| Flutter環境 | `flutter --version`, `flutter doctor -v` | stable SDK取得済み。後からAndroid SDK 36.0.0を検出し、ライセンス承諾済み |
| Dart静的解析 | `flutter analyze` | 成功、No issues found |
| Widget test | `flutter test` | 成功、1件通過 |
| Android debug | `flutter build apk --debug` | 成功。英数字パスの一時cloneでAPK生成 |
| Androidエミュレーター | `adb -e install -r`, `adb -e shell am start`, `am force-stop`後の再起動 | Android 16 / API 36のPixel 8エミュレーターで成功。日本語の準備中画面を視認 |
| iOS Simulator build | `flutter build ios --simulator` | 2026-09-28にMacで成功。`build/ios/iphonesimulator/Runner.app`を生成 |
| iOS device build | `flutter build ios --debug --no-codesign` | 2026-09-28にMacで成功。生成物は署名なし |
| iOS device signing（SSH） | `xcodebuild`で接続中のiPhoneを指定し自動署名を試行 | 正しいPersonal Teamを指定するとProvisioning Profileの処理は進んだが、署名鍵へのアクセスで`errSecInternalComponent`により失敗 |
| iOS Simulator | `simctl install`、`simctl launch`、`simctl terminate`後の再起動 | iPhone 17 / iOS 27.0で成功。日本語の準備中画面をスクリーンショットで視認 |
| iOS実機 | XcodeのRunnerスキームからiPhone 16 Proを指定して実行 | 署名、インストール、起動に成功。`devicectl`でインストールを確認し、利用者のスクリーンショットで日本語の準備中画面を視認 |

作業フォルダとSDKの日本語パスで初回の `flutter analyze` と `flutter test` はFlutter側のパス処理により失敗した。英数字のみの一時ジャンクションから同一ソースとSDKを参照して再実行し、解析とテストは成功した。

Android Studio導入後、`flutter doctor -v` はAndroid SDKと全ライセンスを正常と判定した。ただしジャンクションからのGradleビルドは実パスの非ASCII文字を検出して停止した。英数字パスへコミット `6d88156363ee6e52348bd8119811b1acb9074294` を一時cloneして再実行したところ、Flutter指定のNDK `28.2.13676358` が不足していた。これをAndroid CLIから追加し、debug APKのビルドに成功した。APKは150,368,862バイト、SHA-256は `91DD2D0D19C4048BD8160F34CF8E0CA5A80B7C42CAC0A9BF529E889C69CE0E7C`。一時cloneとAPKはリポジトリ外にあり、コミットしていない。

利用者がPixel 8 / Android 16（API 36）エミュレーターへのAPKインストールで `Success` を確認した。続いてADBで `dev.legionedge.atode_box` を起動し、スクリーンショットで「あとでボックス」「今じゃない。でも忘れたくない。」「入力機能は準備中です」の表示を確認した。`am force-stop` 後の再起動でも同じ画面を確認した。BmaxOSを含むAndroid実機での起動は未検証。

2026-09-28にApple M1 / macOS 26.6.2 / Xcode 27.0のMacでFlutter 3.47.5を使用し、`flutter analyze`（問題なし）、`flutter test`（1件通過）、iOSシミュレーター向けビルド、実機向け署名なしビルドを確認した。iPhone 17 / iOS 27.0シミュレーターでアプリを起動し、「あとでボックス」「今じゃない。でも忘れたくない。」「入力機能は準備中です」の表示を確認した。終了後の再起動にも成功。Mac上の`flutter doctor -v`ではXcodeと端末を検出したが、CocoaPodsは未導入。現時点のプロジェクトにはネイティブiOSプラグインがなく、上記ビルドは成功した。

SSHからの署名付きビルドでは、初回に別の証明書のチームを誤って指定したためアカウントとProfileを見つけられなかった。SimpleAlarmPoCで使用したPersonal Teamに訂正すると、署名鍵へのアクセスで`errSecInternalComponent`が発生した。Mac上のローカルコピーだけにTeam設定を入れ、Xcode本体からRunnerをiPhone 16 Pro / iOS 26.7へ実行すると、署名・インストール・起動に成功した。`devicectl`でも`dev.legionedge.atodeBox`のインストールを確認した。Team設定と署名情報はリポジトリにコミットしていない。

後続でAndroid実機での起動を確認する。iPhone実機では起動と初期画面のみ確認済みで、アプリ終了後の再起動や後続機能の動作は未検証。Phase 1の登録・分類・保存・通知は未実装。

環境要件の参照元: [Flutter Androidセットアップ](https://docs.flutter.dev/platform-integration/android/setup)、[Flutter iOSセットアップ](https://docs.flutter.dev/platform-integration/ios/setup)（2026-09-28再確認）。

## Issue #5: 生活時間設定と初回案内

2026-09-29にWindowsの英数字パスの一時ジャンクションから `flutter analyze` と `flutter test` を実行し、解析は問題なし、24テストはすべて成功した。Widget testで初回と再起動相当の2回目の案内表示、時刻選択で17:30への変更、休日切替、保存失敗時の再試行を確認した。ローカル保存の再読込と、保存成功後だけ返る設定変更情報もテストした。これらは自動テストの結果であり、端末の画面操作結果ではない。

[PR #28のGitHub CI](https://github.com/legion-edge/atode-box/actions/runs/36444049003)では解析、テスト、Android debug APK、iOS simulator buildの4ジョブが成功した。WindowsローカルのFlutter実行は日本語パスと権限の制約があり、ジャンクションからの解析・テスト結果とCIのAndroidビルド結果を区別する。WindowsローカルではAndroid APKビルドとAndroid端末操作を実施していない。

Macの隔離コピー（HEAD `67989bb`）では `flutter build ios --simulator --no-codesign` が成功し、iPhone 17 / iOS 27.0シミュレーターで初回案内の18:00、19:00、土日・日本の祝日と2つの選択肢をスクリーンショットで視認した。隔離コピーにのみ一時的に `integration_test` を追加し、シミュレーター上で「設定を変更する」から時刻を17:30へ変更、土日をオフ、保存、リポジトリ再読込、2回目の表示で案内が出ないこと、設定画面に17:30が残ることを操作テストで確認した（1件成功）。この一時テストと依存変更はPRへコミットしていない。

2026-09-29にiPhone 16 Pro / iOS 26.7実機でPR HEAD `54f14d4` を検証した。Macの隔離コピーにだけ既存のPersonal Team設定を適用し、Xcode GUIで署名付きビルドを成功させた。無料Personal Teamのアプリ数上限により専用Bundle IDでの追加インストールは失敗したため、既存の `dev.legionedge.atodeBox` を上書きしてインストール・起動に成功した。SSHシェルからの署名は既知の `errSecInternalComponent` で失敗したが、MacのGUIセッションのTerminalから実行した一時的な `integration_test` は成功した（1件）。実機上で設定画面から帰宅開始を17:30へ変更し、保存後のローカル再読込、再表示時の初回案内非表示、設定画面での17:30保持を確認した。テストは終了時に元の生活時間設定を復元した。実機の保存ファイルをMacへコピーする操作は自動承認審査で却下されたため実施していない。一時テスト、Personal Team設定、署名情報、実機データはコミットしていない。端末のOS通知は後続Issueの対象。

## Issue #7: OSローカル通知と3アクション

2026-09-29、Windowsの英数字パスの一時ジャンクションから `flutter analyze`（問題なし）と `flutter test`（38件すべて成功）を確認した。通知ポートの単体テストは、権限拒否中の保存、許可後の予約復元、「開く」のactive維持、「完了」の取消、「あとで」の1回だけの永続更新、OS予約失敗後の再試行を含む。

コミット `b41dbb6` を利用者専用の英数字パスへ一時cloneし、専用Gradleキャッシュと一時コピーのみのファイル監視無効設定で `flutter build apk --debug` が成功した。通常の日本語パスからのビルドは共有Gradleキャッシュのロックで失敗し、一時コピーへの切替後も前のデーモンがロックを保持したため、別の専用コピーとキャッシュで成功した。再発防止手順を `AGENTS.md` に記録した。

Android 16 / API 36エミュレーターには、既存アプリのデータを保護するため一時コピーだけに別のアプリIDを付けてインストールした。通知拒否後も登録が成功し、後から許可してアプリを再起動すると同じ通知IDと3アクションで予約された。検証用保存データの時刻だけを短縮して実配信を確認した。最初の通知は予定UTC 17:26:14に対してAndroidログ上17:26:53に表示された。「開く」で内容表示とactive維持、「あとで」でsnooze_count 1と新しいOS予約、「完了」でcompletedとOS予約0件を確認した。端末再起動後はロック解除後にアラームが復元された。これはエミュレーター結果であり、Android実機での到達時刻と動作は未検証。

このWindows環境ではXcodeとiOSシミュレーターを利用できない。Mac環境は前述のとおり存在するが、この作業セッションからiOSビルド、iOSシミュレーター、iPhone実機操作は実施していない。新しいネイティブプラグインのiOSビルドはPRのmacOS CIで別途確認する。Macで実機検証する際はCocoaPodsを用意し、通知許可・拒否、3アクション、端末再起動、URLを開いた後のactive維持を確認する。
