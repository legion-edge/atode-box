# Windows Androidビルドの容量管理（第1段階）

`scripts/Invoke-WindowsAndroidBuild.ps1` はcommit済みの利用者専用英数字パスcheckoutから、Android arm64 debug APKをビルドする。clone・SDK導入・端末install・daemon停止は行わない。解析/test/iOS手順の代替ではない。

```powershell
.\scripts\Invoke-WindowsAndroidBuild.ps1 -TaskId issue-35 -ReasonCode NewTask -ExpectedCommit <40桁の確認済みHEAD> -GradleUserHome C:\Users\KAIL\AtodeBuildCache\slot-a -StateDirectory C:\Users\KAIL\BuildGuard\atode -ExpectedPeakGB 8 -ReserveGB 30 -DryRun
```

まず `-DryRun` で残量・HEAD・clean状態を確認し、実ビルドは `-DryRun` を外す。PATH上の確認済み `flutter.bat` を使う。`android/build.gradle.kts` の `../../build` 出力を維持する。日本語実パスのGradle障害と9.3.1の残存daemonロックを理由に隔離が必要だった経緯を保持し、一般の `.gradle` や他taskのhomeへ切り替えない。

- 初回の専用homeは新規または空とし、理由を `NewTask` / `IsolatedValidation` / `Recovery` で記録する。別taskが記録したhomeは使用を拒否する。専用homeは同じstateに最大2個まで記録し、追加は所有者の停止・参照・archive/整理レビュー待ちとする。失敗/未完了homeの再使用は保留。毎回新しいhomeを無制限に増やさない。
- 成功済みの同一task/homeを再実行する場合も、所有者がdaemon参照・ロック障害の不存在を先に確認する。wrapperの排他だけで既存daemonの非参照は証明できない。**異なるtask間のcache共有は検証・承認前に本適用しない。** 検証ではGradle/JDK/Flutter/Android依存条件、同時実行、障害回復を扱う。
- 同じrepoの全taskで同じ利用者専用 `StateDirectory` を使う。stateを変えて上限・排他を回避しない。NAS/UNC・リムーバブルdrive・リンク経由は拒否する。sourceとstateをPublic等の共有場所へ置かない。
- 空き100 GB（10^9 bytes）未満は警告。新規大型隔離ビルドは60 GB未満で保留。出力先/state先の予定ピーク＋録画・OS余裕（初期30 GB）も確認する。稼働中処理は停止しない。並行task分は所有者が合算する。
- 同一stateのwrapperはOSファイル排他で逐次化する。失敗時もhandle・作業ディレクトリ・Gradle環境を復元する。既存daemonの停止・他起動経路の制御は含まない。
- APKはtask/commit/SHA-256/bytesを持つローカル保全一覧へ保存する。同一SHA・名前は再コピーせず、既存成果物は上書きしない。最大8成果物/task、64 manifest/state。上限では保留し、人のarchiveレビューを要求する。manifestは最新実行1件＋保全一覧で、生ログ・引数・環境全体・秘密値を記録しない。
- 成功時の `build` 整理候補は、所有者による非使用・APK照合・再利用予定確認と本人の正確なパス承認が必要。Gradle homeは自動候補にせず、daemon参照を別に確認する。失敗時は整理候補なし。元repo、source、Git、未commit退避、trial証拠、ユーザー動画を保持する。
- 自動削除・NASコピー・daemon停止・OS設定変更は含まない。NAS退避はコピー許可→SHA照合→元削除の別承認に分ける。

テスト: `pwsh -NoProfile -File scripts/Test-BuildGuard.ps1`、commit後に `pwsh -NoProfile -File scripts/Test-BuildWrapper.ps1`。疑似exeとmanifest、失敗するfake commandだけを使い、実APKビルド・install・ネットワーク・削除は実行しない。fixtureは確認用に残る。Windows PowerShell 5.1は構文確認済みだが、実行は端末policyで拒否され未検証。policyを変更・迂回して検証しない。

参考: [Gradle directories/caches](https://docs.gradle.org/current/userguide/directory_layout.html)（2026-10-03確認）。専用cache隔離の解消・共有化は別検証工程。
