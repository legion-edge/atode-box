# Windows Androidビルドの容量管理（第1段階）

`scripts/Invoke-WindowsAndroidBuild.ps1` はcommit済みの利用者専用英数字パスcheckoutから、Android arm64 debug APKをビルドする。clone・SDK導入・端末install・daemon停止は行わない。解析/test/iOS手順の代替ではない。

```powershell
.\scripts\Invoke-WindowsAndroidBuild.ps1 -TaskId issue-35 -ReasonCode NewTask -ExpectedCommit <40桁の確認済みHEAD> -GradleUserHome C:\Users\KAIL\AtodeBuildCache\slot-a -StateDirectory C:\Users\KAIL\BuildGuard\atode -ExpectedPeakGB 8 -ReserveGB 30 -ConcurrentPeakGB 0 -DryRun
```

まず `-DryRun` で残量・HEAD・clean状態を確認し、実ビルドは `-DryRun` を外す。PATH上の確認済み `flutter.bat` を使う。`android/build.gradle.kts` の `../../build` 出力を維持する。日本語実パスのGradle障害と9.3.1の残存daemonロックを理由に隔離が必要だった経緯を保持し、一般の `.gradle` や他taskのhomeへ切り替えない。

- 初回の専用homeは新規または空とし、理由を `NewTask` / `IsolatedValidation` / `Recovery` で記録する。別taskが記録したhomeは使用を拒否する。専用homeは同じstateに最大2個まで記録し、追加は所有者の停止・参照・archive/整理レビュー待ちとする。失敗/未完了homeの再使用は保留。毎回新しいhomeを無制限に増やさない。
- 成功済みの同一task/homeを再実行する場合も、所有者がdaemon参照・ロック障害の不存在を先に確認する。wrapperの排他だけで既存daemonの非参照は証明できない。**異なるtask間のcache共有は検証・承認前に本適用しない。** 検証ではGradle/JDK/Flutter/Android依存条件、同時実行、障害回復を扱う。
- 同じrepoの全taskで同じ利用者専用 `StateDirectory` を使う。stateを変えて上限・排他を回避しない。NAS/UNC・リムーバブルdrive・リンク経由は拒否する。sourceとstateをPublic等の共有場所へ置かない。
- 空き100 GB（10^9 bytes）未満は警告。全taskで予定消費後60 GiB未満なら保留。出力先/state先の予定ピーク＋録画・OS余裕（初期30 GB）も確認する。稼働中処理は停止しない。並行task分は所有者がConcurrentPeakGBに明示する。
- 同一stateのwrapperはOSファイル排他で逐次化する。失敗時もhandle・作業ディレクトリ・Gradle環境を復元する。既存daemonの停止・他起動経路の制御は含まない。
- APKはtask/commit/SHA-256/bytesを持つローカル保全一覧へ保存する。同一SHA・名前は再コピーせず、既存成果物は上書きしない。最大8成果物/task、64 manifest/state。上限では保留し、人のarchiveレビューを要求する。manifestは最新実行1件＋保全一覧で、生ログ・引数・環境全体・秘密値を記録しない。
- 成功時の `build` 整理候補は、所有者による非使用・APK照合・再利用予定確認と本人の正確なパス承認が必要。Gradle homeは自動候補にせず、daemon参照を別に確認する。失敗時は整理候補なし。元repo、source、Git、未commit退避、trial証拠、ユーザー動画を保持する。
- 自動削除・NASコピー・daemon停止・OS設定変更は含まない。NAS退避はコピー許可→SHA照合→元削除の別承認に分ける。

テスト: `pwsh -NoProfile -File scripts/Test-BuildGuard.ps1`、commit後に `pwsh -NoProfile -File scripts/Test-BuildWrapper.ps1`。疑似exeとmanifest、失敗するfake commandだけを使い、実APKビルド・install・ネットワーク・削除は実行しない。fixtureは確認用に残る。Windows PowerShell 5.1は構文確認済みだが、実行は端末policyで拒否され未検証。policyを変更・迂回して検証しない。

参考: [Gradle directories/caches](https://docs.gradle.org/current/userguide/directory_layout.html)（2026-10-03確認）。専用cache隔離の解消・共有化は別検証工程。


## 容量再発防止の追加条件（2026-10-04）

GB引数は10^9 bytes、GiBは2^30 bytes。本人が指定した下限は **60 GiB = 64,424,509,440 bytes** とする。旧版の「新規隔離だけ60 GB」は使わない。

全ReasonCode（ExistingTaskを含む）で、開始前と排他取得後に `空き - ExpectedPeakGB - ConcurrentPeakGB >= max(60 GiB, ReserveGB)` をbytesに換算して判定する。ReserveGBは消費予算ではなく、消費後に残す希望容量。初期30 GBは60 GiBの内側に含み、70 GB等の大きい指定は優先する。小さいReserveGBやExistingTaskで下限を緩めない。

`ConcurrentPeakGB` は必須の明示宣言。同じディスク上の別repo/taskのビルド、録画、予測できるOS・ページファイル等の追加消費を合算する。0は所有者が他の増分予定を確認した場合だけ指定する。ExpectedPeakGBには自己ビルド・依存取得・保全コピーの増分を含める。異なるrepo間の排他や、未知のOS消費の自動検出は行わない。

ビルド終了後も下限を確認し、保全コピー直前にはコピー量と並行予算を使って再判定する。最後の保全照合後、成功記録の直前にも下限を確認する。不足なら元生成物を保持して失敗/所有者レビュー待ちとし、成功や整理候補を出さない。既に進行中のビルドは停止しない。開始後の未知の消費を自動停止で制御する仕組みではなく、予算宣言と開始抑止である。宣言条件が変わった場合は別の大型処理を開始せず、本人へ残量を報告する。

DryRunとmanifestに予算、測定時刻、bytes残量、予定ピーク後残量、下限を記録する。ビルド後/最後の照合後の測定は下限不足で失敗してもbytes実測を残す。manifest schemaVersionは1を維持して追加フィールドを使い、旧記録を自動削除・書換えしない。保全済み成果物の再使用もサイズとSHAの両方を検証する。

## 対象分類と保持判断

| 分類 | 扱い・保全条件 | 日数の扱い |
| --- | --- | --- |
| source、Git、未commit退避、Cookie/資格情報、利用者データ | 保護対象。整理候補に含めず内容を監査出力しない | 期限による削除対象にしない |
| 進行中/参照中のbuild、trial、録画 | ownerが非使用と再試験不要を確認するまで保持 | 日数に関係なく保持 |
| 成功済みの再生成可能build/incremental | 明示候補、正確なpath/サイズ、非参照、比較exe/APK/PDB/証拠の保全を確認。manifestは分類付き承認待ちを出すだけ | 完了後7日または14日のレビュー提案。未採用で自動実行しない |
| 失敗/未完了build・専用cache | 原因・証拠・再試験予定をownerが確認。失敗homeを黙って再利用しない | 原因確認前の期限なし |
| 比較exe/APK/PDB・試験証拠 | 最新採用候補と必要な比較候補を保持。最大8/taskを超える場合はownerレビュー | タスク完了後30日でレビューする案。未採用、削除期限ではない |
| SDK、Rust/toolchain、共有依存cache、Gradle home | 本段階の自動候補に含めない。参照・互換性・ロック/daemon確認と別承認が必要 | 日数だけで整理しない |
| MP4等の保存媒体 | 正確な個別pathのみ。NASコピー/照合と原本削除承認は別操作 | 退避照合前は保持。照合後も日数だけで削除しない |
| pagefile、hiberfil、Windows管理領域 | 観測できる容量だけを報告。設定変更/削除/権限迂回をしない | 本段階の整理対象外 |

レビュー時期案はownerへの候補提示の目安であり、削除承認ではない。必要なtaskの比較物を単純な「最新N件」で消さない。保持日数が未回答ならレビュー日時を登録せず、従来どおりowner確認待ちを維持する。今回のwrapperに自動削除job、定期実行、NAS転送は追加しない。

## 退避後の原本整理に必要な条件

1. 承認対象の元pathと転送先pathを取り違えず、最新の非参照確認とリンク境界確認を行う。
2. コピー処理のcompleteだけでなく、対象全件のverifiedに元/先のbytesとSHA-256一致が記録されていることを確認する。partialやバッチ途中失敗は完了扱いしない。
3. 照合後に元のsize/mtimeが変わった場合やNAS先が確認不能の場合は、過去のhash一致を削除根拠に流用しない。必要な再照合は別途調整し、失敗を成功扱いしない。
4. 再試験/再利用予定、必要な比較成果物・証拠の保全をownerが確認し、正確な元pathとサイズを本人に提示する。
5. 本人の原本削除承認を別に得る。コピー許可・候補出力・保持日数・verifiedを削除承認として扱わない。過去に削除完了したpathを再度処理しない。

## 導入と検証の境界

この変更は未公開のDraft候補。最新mainに整合した専用branchをcommitし、正規承認解決後に通常pushとDraft PR本文の読み戻しを行う。force push、main書込み、merge、Release、手動CI起動をこの承認に含めない。全taskへwrapper使用を揃える導入はowner調整後で、別経路のCargo/Flutterを本段階で強制停止しない。

模擬テストは既存task低容量、GB/GiB境界、ピーク後下限、並行予算、終了後急減、保全コピー前の下限、元保全、分類/予算の記録を含む。実アプリビルド、NAS送信、本番削除は行わない。
