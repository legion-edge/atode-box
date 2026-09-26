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
- シミュレータ、実機、静的解析、資料確認を分けて報告する。成功していない検証を成功と記載しない。
- 公式資料で技術事実を確認したら、関連文書またはPRにURLと確認日を残す。
- APIキー、署名鍵、認証情報、個人データ、生ログ、ローカル設定をコミットしない。`.gitignore` と差分を確認する。
- UI文言は日本語を基本とし、処理と分離して将来の多言語対応を妨げない。

## GitHubと完了条件

- Issue、PR本文は原則日本語。本文には背景、変更、対象外、テスト／未実施理由、残課題を実際の改行で記載する。投稿後は読み戻す。
- 各IssueのDefinition of Doneは、Acceptance Criteriaの確認、適切な検証、未検証事項の明記、差分確認、commit、push、Issueに紐づくPR作成を含む。レビュー・mergeは別工程。
- `git diff --check`、ステージ後の `git diff --cached --check` を実行する。未追跡ファイルは読み取り、ステージ後にも確認する。
- ユーザーの明示依頼なしにmainへmergeしない。終了時には変更、実行コマンド、結果、未検証事項、次のIssueを報告する。

## 参考元

2026-09-27に [Simple Media DownloaderのAGENTS.md](https://github.com/legion-edge/simple-media-downloader/blob/main/AGENTS.md)、最新Issue #100、README、ロードマップを確認し、Issue運用と検証の汎用ルールを調整した。Windows/Tauri、yt-dlp、FFmpeg、配布・Cookie・動画取得の固有手順は取り込んでいない。SMDのタスク間レビュー連絡先は本プロジェクトへ適用しない。
