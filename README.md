# あとでボックス

> 今じゃない。でも忘れたくない。

あとで確認したいURL、行きたい場所、買いたいもの、アイデアやメモを、整理せずにすばやく保存するモバイルアプリです。保存内容の性質と生活時間から、処理しやすいタイミングで思い出せることを目指します。

## 現在地

Phase 1の初期構成です。iOS / Android向けFlutterプロジェクトと設計文書を用意しています。登録・分類・保存・通知の一連の動作は後続Issueで実装します。現時点の画面や雛形を利用可能な完成機能として扱わないでください。

## 開発

Flutter stableと対象プラットフォームのツールチェーンを用意し、リポジトリのルートで実行します。

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

iOSビルドにはmacOSとXcodeが必要です。Windows上でのDart解析・テストは、iOS実機／シミュレータ検証の代わりにはなりません。

## 文書

- [MVPと開発フェーズ](docs/MVP.md)
- [構成と拡張境界](docs/ARCHITECTURE.md)
- [ドメイン概念](docs/DOMAIN.md)
- [開発・検証ルール](AGENTS.md)
- [初期構成の検証記録](docs/VALIDATION.md)
- [Flutter CI](docs/CI.md)

GitHub Issueを作業の単位とし、各Issueの範囲、受け入れ条件、検証結果を記録します。
