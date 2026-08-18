# YamaLens CI方針

この文書は、GitHub Actions、CI、必須Status Check、自動化用Secretを扱うときに使用する。CIはPull Requestの早期検知と再現可能な自動検証を担い、実機・現地検証を代替しない。

## 目次

1. 基本方針
2. 実行契機と同時実行
3. 段階的な導入
4. Repository validation
5. Xcodeビルド・テスト
6. 権限とSecret
7. Actionと依存の固定
8. 成果物、キャッシュ、ログ
9. 必須Status Check
10. 失敗時の扱い
11. ローカル再現
12. 実機・現地との境界
13. 公式参考資料

## 基本方針

- GitHub Actionsを使用し、Pull Requestで統合前、`main`へのpushで統合後、`workflow_dispatch`で必要時に検証する。
- Workflowは検証だけを行い、コード修正、commit、push、Pull Request承認、マージを自動実行しない。
- CIで実行する処理は、可能な限りリポジトリ内の `Scripts/CI/` に置き、ローカルでも同じコマンドを実行できるようにする。
- Job名はBranch protectionの必須Checkとして使うため、意味なく変更しない。
- Xcode、OS、シミュレーターの版を明示し、`macos-latest`の暗黙更新だけに依存しない。
- 速さのためにテスト、Swift 6並行性検査、安全確認を無効化しない。

## 実行契機と同時実行

- `pull_request`: `main`向けの作成、更新、再開で実行する。
- `push`: `main`への統合結果を実行する。
- `workflow_dispatch`: Runner更新、障害調査、保護規則設定前の確認に使用する。
- 同じWorkflow・同じブランチで古い実行が残っている場合はキャンセルし、最新の変更を優先する。
- 定期実行は、外部データ、依存更新、Runner更新を監視する具体的な目的が生じるまで追加しない。

## 段階的な導入

### 第1段階: コードがない現在

- `Repository validation` Jobを必須候補とする。
- スキル構造、必須文書、Markdownの内部リンク、追跡禁止ファイル、コンフリクトマーカーを検証する。
- Xcodeプロジェクトがないことを成功扱いでスキップするJobは作らない。

### 第2段階: Xcodeプロジェクト作成時

- プロジェクト、共有Scheme、既定Test Planと同じPull Requestで `Xcode build and test` Jobを追加する。
- `macos-26` Runner、`/Applications/Xcode_26.6.app`、iPhone 17 Pro／iOS 26.5シミュレーターを使用する。
- `CODE_SIGNING_ALLOWED=NO` とテスト用固定依存を使用し、Developer証明書、WeatherKit認証、実ネットワークを必要としない構成にする。
- Job追加後、`main`または保護前のPull Requestで安定して成功することを確認してから必須Checkへ設定する。

### 第3段階: UIテストとリリース

- 重要導線のUIテストが安定した後、通常のCIへ含める。再実行しないと通らないテストを必須Checkにしない。
- TestFlightや署名付きArchiveは、MVPの実機検証が安定し、明示的な配布運用を決定してから別Workflowとして設計する。
- リリースWorkflowは `workflow_dispatch` と保護Environmentを使用し、Pull Request由来コードから直接実行しない。

## Repository validation

現在の `.github/workflows/ci.yml` はUbuntu上で次を確認する。

- 必須の仕様書、リポジトリ指示、スキル参照、PRテンプレート、`.gitignore`が存在すること。
- `SKILL.md`のfrontmatterが `name` と `description` だけを持ち、値が有効であること。
- Markdownの相対リンク先が存在すること。
- `.DS_Store`、認証・署名情報、Xcode個人設定、テスト結果、生成データがGit追跡されていないこと。
- 未解決のGitコンフリクトマーカーがないこと。

検証本体は `bash Scripts/CI/validate-repository.sh` とし、GitHub Actions専用APIを使わずローカルで再現可能にする。

## Xcodeビルド・テスト

Xcodeプロジェクト作成後は、共有SchemeとTest Planを指定して次の意味のコマンドを実行する。

```sh
xcodebuild test \
    -project YamaLens.xcodeproj \
    -scheme YamaLens \
    -testPlan YamaLens \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
    -derivedDataPath "$RUNNER_TEMP/DerivedData" \
    -resultBundlePath "$RUNNER_TEMP/YamaLensTests.xcresult" \
    CODE_SIGNING_ALLOWED=NO
```

- ProjectからWorkspaceへ変更した場合は同じPull RequestでWorkflowも更新する。
- SchemeとTest Planを共有設定としてGitへ登録する。
- `xcodebuild`の終了コードをパイプで失わない。整形ツールを追加する場合は `pipefail` を有効にする。
- Runner内の利用可能なシミュレーターが変更された場合は、GitHub公式Runner image一覧を確認して明示的に更新する。
- UIテストを分離する必要が生じるまでは、一つのTest PlanとJobで全自動テストを実行する。

## 権限とSecret

- Workflow全体の権限は `permissions: contents: read` を既定とする。
- Jobが追加権限を必要とする場合だけ、そのJobへ最小権限を明示する。
- `pull_request_target`を使用しない。Pull Request由来の任意コードと基準ブランチの書き込み権限・Secretを同時に扱わない。
- forkからのPull Requestを含め、通常CIへApple Developer、WeatherKit、署名、地図サービス等のSecretを渡さない。
- Secret値をコマンドライン、ログ、成果物、テストAttachmentへ出力しない。
- 署名や配布が必要になった場合は、通常CIから分離した手動Workflow、GitHub Environment、最小権限、承認手順を設計する。

## Actionと依存の固定

- 外部Actionは完全なcommit SHAへ固定し、行末コメントに確認した版を記載する。
- GitHub公式Actionも同じ規則で固定する。
- GitHub Actions用Dependabotを月次で動かし、更新Pull Requestでも通常CIを実行する。
- Actionの更新ではRelease notes、権限、Nodeランタイム、破壊的変更を確認する。
- CI中に `curl | sh`、未固定ブランチ、任意の最新スクリプトを実行しない。

## 成果物、キャッシュ、ログ

- 初期は依存とビルド時間を計測するまでキャッシュを追加しない。不正なキャッシュや複雑なキーを保守するコストを避ける。
- Xcodeテスト失敗時は `.xcresult` を短期間だけ保存し、正確な位置、個人メモ、カメラ映像、Secretが含まれないことを確認する。
- 大容量オフラインパック、DerivedData、Archiveを通常CIの成果物として保存しない。
- ログにXcodeとRunner imageの版、実行コマンド、テスト結果を残す。
- 成果物アップロードActionを追加する場合もcommit SHAへ固定し、保持期間を明示する。

## 必須Status Check

- 現段階の必須候補は `Repository validation` とする。
- Xcodeプロジェクト作成後は `Xcode build and test` を必須候補へ追加する。
- Checkを必須化する前に、対象Workflowを既定ブランチで一度成功させ、Job名がGitHubの設定画面へ表示されることを確認する。
- 不安定、実ネットワーク依存、Secret依存、実機依存のJobをPull Requestの必須Checkにしない。
- Branch protection設定は外部状態の変更なので、ユーザーの明示依頼を受けてから行う。

## 失敗時の扱い

- CI失敗を再実行だけで通さない。仕様、実装、テスト、Runner更新、Workflowのどこに原因があるか確認する。
- Runner障害が疑われる場合はGitHub StatusとRunner imageの変更履歴を確認し、ローカル結果と区別する。
- 必須Checkを無効化してマージするのではなく、原因修正または安全なrevertを優先する。
- GitHub側の障害で緊急対応が必要な場合だけ管理者バイパスを検討し、理由とローカル証拠をPull Requestへ残す。
- Workflow変更自身は、権限拡大、Secret参照、イベント、Shell展開、Action参照を重点的にレビューする。

## ローカル再現

- Repository validationは `bash Scripts/CI/validate-repository.sh` で実行する。
- Xcode Job追加後は、`$RUNNER_TEMP`をローカルの一時ディレクトリへ置き換え、同じ `xcodebuild` 引数で実行する。
- CIだけで失敗する場合は、Xcodeの版、Simulator runtime、CPUアーキテクチャ、ロケール、タイムゾーン、ファイル名の大文字小文字を比較する。
- ローカルだけで成功するテストは、時刻、実行順序、共有状態、権限、実ネットワークへの依存を疑う。

## 実機・現地との境界

- GitHub-hosted RunnerはiPhone 15 Pro実機ではない。iPhone 17 Proシミュレーター成功を対応実機の保証として扱わない。
- カメラ映像、真北方位、Core Motion、レンズ別画角、発熱、電池、屋外の視認性は実機で確認する。
- WeatherKitの実認証、Apple Maps／Google Maps遷移は実機確認を別に記録する。
- 丹沢で実際に見える山、遮蔽物、ラベルずれ、手動補正は現地検証を正とする。
- CI結果、ローカル結果、実機結果、現地結果をPull Requestと引き渡し報告で区別する。

## 公式参考資料

- [GitHub Docs: Workflow syntax for GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [GitHub Docs: Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub Docs: GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)
- [GitHub Actions Runner Images](https://github.com/actions/runner-images)
- [macOS 26 Runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
