# Flutter CI

`main` 向けPull Requestと `main` へのpushで `.github/workflows/flutter-ci.yml` を実行する。Flutterは3.47.5に固定する。PRへの追加pushでは同じPRの実行中ワークフローを取り消し、最新コミットを検証する。ブランチへの通常のpushでは起動しないため、PR作成前の重複実行を避ける。

| チェック | ランナー | 実行内容 |
| --- | --- | --- |
| Analyze | Linux | `flutter pub get`、`flutter analyze` |
| Test | Linux | `flutter pub get`、`flutter test`（全テスト） |
| Android debug APK | Linux | `flutter pub get`、`flutter build apk --debug` |
| iOS simulator | macOS | `flutter pub get`、`flutter build ios --simulator --no-codesign` |

各チェックは独立したジョブで、失敗したコマンドのログはGitHub Actionsの該当ジョブで確認できる。Flutter SDKとpub依存パッケージをOS・Flutterバージョン別にキャッシュし、AndroidではGradle依存パッケージもキャッシュする。`GITHUB_TOKEN` はリポジトリ内容の読み取り権限だけを持つ。

ローカルでもリポジトリのルートから表のコマンドを実行できる。AndroidビルドにはAndroid SDKとJDK 17、iOSビルドにはmacOSとXcodeが必要。CIはビルドの成立を確認するが、エミュレーター／シミュレーターでの起動、実機テスト、署名付き配布ビルド、ストア公開は実施しない。署名鍵、Personal Team設定、シークレットは使用しない。

設定の参照元: [Flutter actionのバージョン指定とキャッシュ](https://github.com/subosito/flutter-action)、[checkout](https://github.com/actions/checkout)、[setup-java](https://github.com/actions/setup-java)、[GitHub Actionsの権限・並列実行設定](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)、[FlutterのiOSビルド要件](https://docs.flutter.dev/platform-integration/ios/setup)（2026-09-28確認）。
