# あとでボックス開発ルール

## 作業前

- GitHubを正本とする。対象Issueの背景、Scope、Out of Scope、Acceptance Criteria、Definition of Doneと `docs/MVP.md` を読む。
- `git status --short --branch` と `git fetch origin main` で作業状態・最新mainを確認する。取得失敗時は成功扱いにしない。
- 最新 `origin/main` を起点に `codex/` ブランチで1 Issueずつ作業する。既存変更を混在・破棄せず、mainを直接編集しない。初回の空mainコミットのみ例外とする。
- Issue外の大規模変更を勝手に追加しない。後続Issueの機能を先回りしない。依存関係は必要性と保守負担を確認して追加する。

## 製品方針

- 日本語利用者を第一対象とし、入力時の分類・整理・時刻指定を強制しない。「Discordより面倒にならない」を操作設計の基準にする。
- カテゴリは7種。色だけに頼らず文字とアイコンを併用する。
- 通知日時はアプリの決定的なルールエンジンで決める。将来のAIは分類などの属性判定までとし、日時を自由生成させない。AIやネットワークがなくてもPhase 1の基本機能を成立させる。
- `active`、`completed`、`deleted` を基本状態とし、「あとで」は回数と次回通知日時で表す。「開く」は完了扱いしない。
- iOS / Android両方を対象に保つ。片方で検証できない場合はプラットフォームを削らず、未検証と理由を記録する。

## 実装と検証

- 変更に応じた `flutter analyze`、`flutter test`、対象OSビルドと代表操作を実施する。文書だけの変更ではMarkdownリンク、整合性、`git diff --check` を確認する。
- Windowsでは、このリポジトリと同梱Flutter SDKの実パスに日本語が含まれる。日本語パスから直接 `flutter analyze` / `flutter test` を始めない。利用者専用の英数字パスに一時ジャンクションを作り、そこを作業ディレクトリとしてFlutterを実行する。テスト用シェーダーの生成は日本語パスで失敗することがある。`flutter analyze` の解析サーバーが失敗した場合は同じ英数字パスから再実行し、失敗を成功扱いにしない。
- WindowsのAndroidビルドではジャンクションだけではGradleが日本語の実パスを参照して失敗する。先に変更をコミットし、利用者専用の英数字パスの一時ディレクトリへそのコミットをcloneしてビルドする。共有フォルダ（`C:\Users\Public`など）にソースを複製しない。ビルド用コピーのHEADを確認し、必要なら専用のGradleキャッシュを使う。作業終了後は保全manifestと参照状態を確認し、一時コピー・生成物・ジャンクションの整理候補を本人へ提示する。承認なしで解除・削除しない。
- このWindows環境のGradle 9.3.1では残存daemonの共有cacheロックでビルドが失敗した経緯がある。隔離理由を保持し、無制限に新しい `GRADLE_USER_HOME` を増やさない。第1段階wrapperは理由を記録した専用homeを最大2個に制限し、別task間共有と未完了/失敗homeの再利用は保留する。同一taskの成功済みhomeを再実行する場合も所有者がdaemon参照とロック障害の不存在を確認する。共有化は互換条件・競合・障害回復の検証と別承認後に扱う。ファイル監視障害時の一時コピーだけの `org.gradle.vfs.watch=false` を維持し、本体へ混ぜない。
- シミュレータ、実機、静的解析、資料確認を分けて報告する。成功していない検証を成功と記載しない。
- 公式資料で技術事実を確認したら、関連文書またはPRにURLと確認日を残す。
- APIキー、署名鍵、認証情報、個人データ、生ログ、ローカル設定をコミットしない。`.gitignore` と差分を確認する。
- UI文言は日本語を基本とし、処理と分離して将来の多言語対応を妨げない。

## Windowsローカルビルドの容量・保全

- 大型ローカルビルドの前に [容量管理手順](docs/LOCAL_BUILD_STORAGE.md) のwrapperを `-DryRun` で確認する。空き100 GB未満は警告、全task（既存も含む）は予定増加と明示したConcurrentPeakGBを差し引いた残量が60 GiB（64,424,509,440 bytes）またはReserveGBを下回れば保留する。GB引数は10^9 bytes、ReserveGBは消費後の希望残量。別repoビルド・録画・予測OS増分を並行予算に合算する。進行中処理を停止しない。
- 同じrepoの全taskは同じ利用者専用ローカルStateDirectoryを使う。新しいbuild/cache領域はtask・確認済みcommit・列挙した新設理由を記録する。state変更で排他・上限を回避しない。
- wrapperは同一stateのビルドを逐次化し、成果物をSHA-256付きで保全する。manifest最大64 task、成果物最大8/task。上限・不完全コピー・未完了cacheでは所有者レビュー待ちとし、未記録の領域を増やして回避しない。
- task完了時は所有者が参照・再試験予定・比較exe/APK/PDB/証拠の保全を確認し、正確なパスとサイズの整理候補を本人へ報告する。候補の出力は削除承認ではない。承認時点で境界・リンク・参照・保全SHAを再確認する。
- 保持日数は削除期限にせず分類別のレビュー時期として本人へ提案する。未回答の値や自動実行範囲を確定扱いしない。退避後も全件のsize/SHA照合・最新の元size/mtime・非参照・別の原本削除承認が必要。過去完了pathを再処理しない。
- 自動削除、日数だけの削除、NAS送信、daemon停止、OS設定変更はwrapperに含めない。元repo・source・Git・未commit退避・現在のtrial・ユーザー動画は保全する。NAS退避はコピー許可・SHA照合・原本削除承認を分ける。

## iOS検証環境

2026-09-28時点の検証環境は Apple M1 / macOS 26.6.2 / Xcode 27.0 / Flutter 3.47.5。iOSビルド・実行はMacとXcodeで行う。`flutter build ios --simulator` と実機向け `flutter build ios --debug --no-codesign` は成功済み。iPhone 17 / iOS 27.0シミュレーターとiPhone 16 Pro / iOS 26.7実機で初期画面を確認した。

実機の署名・起動はMacローカルのXcodeでRunnerスキームにPersonal Teamを設定して実施した。SSH経由の署名付きCLIビルドはキーチェーンの `errSecInternalComponent` で失敗するため、署名なしビルドの成否と分けて報告する。Team設定や署名情報はコミットしない。2026-09-28時点のMacローカル環境ではCocoaPodsが未導入だった。Issue #7で `flutter_local_notifications` と `url_launcher` のネイティブiOSプラグインを追加し、GitHub CIのiOS simulatorビルドは成功した。Macローカルで再検証する際はCocoaPodsの導入状況を確認する。詳細は [検証記録](docs/VALIDATION.md)。

## GitHubと完了条件

- Issue、PR本文は原則日本語。本文には背景、変更、対象外、テスト／未実施理由、残課題を実際の改行で記載する。投稿後は読み戻す。
- 各IssueのDefinition of Doneは、Acceptance Criteriaの確認、適切な検証、未検証事項の明記、差分確認、commit、push、Issueに紐づくPR作成を含む。レビュー・mergeは別工程。
- `git diff --check`、ステージ後の `git diff --cached --check` を実行する。未追跡ファイルは読み取り、ステージ後にも確認する。
- ユーザーの明示依頼なしにmainへmergeしない。終了時には変更、実行コマンド、結果、未検証事項、次のIssueを報告する。

## 参考元

2026-09-27に [Simple Media DownloaderのAGENTS.md](https://github.com/legion-edge/simple-media-downloader/blob/main/AGENTS.md)、最新Issue #100、README、ロードマップを確認し、Issue運用と検証の汎用ルールを調整した。Windows/Tauri、yt-dlp、FFmpeg、配布・Cookie・動画取得の固有手順は取り込んでいない。SMDのタスク間レビュー連絡先は本プロジェクトへ適用しない。
