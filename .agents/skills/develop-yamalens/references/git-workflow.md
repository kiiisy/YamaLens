# YamaLens Git運用方針

この文書は、ブランチ作成、コミット、Pull Request、マージ、タグ、リリースで使用する。YamaLensは個人開発のMVPであるため、長期ブランチを増やさないGitHub Flowを採用する。

## 目次

1. 基本方針
2. ブランチの種類と命名
3. 作業の流れ
4. コミット規則
5. Pull Request規則
6. マージと履歴
7. mainの保護
8. 緊急修正と取り消し
9. リリースとタグ
10. AIエージェントのGit操作
11. Gitへ含めないもの
12. 公式参考資料

## 基本方針

- `main` だけを長期ブランチとし、常にビルド・検証可能で、既知の重大な不整合がない状態を保つ。
- `develop`、`release`、`hotfix`の常設ブランチを作らない。
- 一つの作業ブランチとPull Requestには、一つの論理的な変更または一つの小さな垂直スライスだけを含める。
- 作業ブランチは数日程度で統合できる大きさを目安とする。長期化する場合は、利用者から見て安全に統合できる単位へ分割する。
- 未完成の大機能を長期間ブランチに保持しない。必要な場合は本番動作へ影響しない小さな内部単位に分けるが、将来機能の仮実装は追加しない。
- 仕様、実装、テスト、データ変更を別々の長期ブランチに分離せず、同じ動作変更に必要なものを同じPull Requestに含める。

## ブランチの種類と命名

ブランチ名は英小文字、数字、ハイフンを使い、`種類/短い説明` とする。Issue番号がある場合は説明の先頭へ付けてよい。

| 接頭辞 | 用途 | 例 |
| --- | --- | --- |
| `feat/` | 利用者向け機能 | `feat/mountain-search` |
| `fix/` | 不具合修正 | `fix/stale-weather-label` |
| `docs/` | 文書だけの変更 | `docs/testing-strategy` |
| `test/` | 動作を変えないテスト整備 | `test/candidate-boundaries` |
| `refactor/` | 動作を変えない内部整理 | `refactor/sensor-adapters` |
| `perf/` | 性能改善 | `perf/candidate-ranking` |
| `build/` | Xcode、依存、ビルド設定 | `build/create-xcode-project` |
| `ci/` | CI設定 | `ci/run-simulator-tests` |
| `chore/` | 上記以外の保守 | `chore/update-gitignore` |
| `spike/` | 結論を得るための破棄可能な調査 | `spike/weatherkit-auth` |

- `feature/ksy/...` のような個人名階層は作らない。
- `update`、`work`、`tmp`のように内容が分からない名前を使わない。
- `spike/` の成果をそのまま本番へマージしない。採用する場合は仕様判断後に本番品質の変更として整理する。

## 作業の流れ

1. `main` の最新状態と作業ツリーの未コミット変更を確認する。
2. `main` から目的に合う短命ブランチを作る。
3. 受け入れ条件を満たす最小の変更、関連文書、対象テストを実装する。
4. 差分に秘密情報、大容量生成物、無関係な変更がないことを確認する。
5. 対象テストを実行し、引き渡し前に利用可能な全ビルド・テストを実行する。
6. Pull Requestへ成果、理由、仕様、テスト、実機・現地の未確認事項を記載する。
7. 指摘と失敗したチェックを解消し、Squash mergeする。
8. マージ後に作業ブランチをリモート・ローカルから削除する。未マージの変更がないことを先に確認する。

作業途中で早い確認が必要な場合はDraft Pull Requestを使用する。無関係な修正を見つけた場合は、現在のPull Requestへ混ぜず別ブランチまたは別Issueへ分ける。

## コミット規則

- コミットメッセージは `<種類>: <日本語の要約>` を基本とする。
- 種類はブランチ接頭辞と同じ `feat`、`fix`、`docs`、`test`、`refactor`、`perf`、`build`、`ci`、`chore` を使用する。
- 命令や変更内容が分かる具体的な要約にする。例: `feat: 山名と別名による検索を追加`。
- `update`、`fix`、`WIP`だけのメッセージを最終履歴へ残さない。
- 一つのコミットには、独立して説明・取り消しできる変更をまとめる。フォーマットだけの大量変更を機能変更へ混ぜない。
- APIキー、署名情報、実際のメモ、正確な位置履歴を一度でもコミットしない。削除コミットを追加しても履歴には残るため、発見時は公開範囲を確認して資格情報を失効する。

作業ブランチ上の修正コミットは許容する。Pull RequestをSquash mergeするため、`main` にはPull Requestの論理的な変更を表す一つのコミットを残す。

## Pull Request規則

- コード、設定、正本文書、スキルの意味ある変更は、原則としてPull Requestを経由する。
- Pull RequestのタイトルはSquash後のコミットとして読める `<種類>: <日本語の要約>` にする。
- 本文に「成果」「変更理由」「仕様・受け入れ条件」「テスト結果」「実機・現地の未確認事項」「画面変更の証拠」を記載する。
- UI変更では、関係する通常・空・失敗・オフライン・権限拒否・低精度・Dynamic Type状態の画像または確認結果を添える。
- 仕様または利用者から見える動作を変更した場合は、関連する正本文書を同じPull Requestで更新する。
- Pull Requestが大きくなり、説明、レビュー、取り消しを一つの目的として扱えない場合は分割する。行数だけを機械的な上限にしない。
- 個人開発中は別人の承認を必須にしない。共同開発へ移行した場合は、1名以上の承認と最新push後の再承認を保護規則へ追加する。

## マージと履歴

- マージ方法はSquash mergeだけを使用し、`main` を一つのPull Requestにつき一つのコミットとなる線形履歴にする。
- Merge commitと通常のRebase mergeは使用しない。
- マージ前に必須チェック、未解決の会話、仕様とテストの整合を確認する。
- `main` へforce pushしない。公開済みの `main` の履歴をrebase、amend、resetで書き換えない。
- 自分だけが使用する未マージの作業ブランチをrebaseする場合に限り、必要なら `--force-with-lease` を使用できる。共有ブランチでは事前合意なしに履歴を書き換えない。
- マージ後の誤りは履歴を書き換えず、revert Pull Requestまたは修正Pull Requestで戻す。

## mainの保護

GitHubで `main` にRulesetまたはBranch protection ruleを設定する。

- Pull Requestを経由しない変更を禁止する。
- force pushとブランチ削除を禁止する。
- 会話の解決を必須にする。
- 線形履歴を必須にし、Squash mergeだけを有効にする。
- CI導入後はビルド、ユニット・結合テストを必須Status Checkにする。安定したUIテストを追加した後は、それも必須化する。
- 個人開発中は承認者数を0とし、自己承認できないためにマージ不能となる設定を避ける。
- 管理者によるバイパスは障害復旧に限定し、通常作業では使用しない。

保護設定そのものはGitHub上の外部状態を変更するため、ユーザーの明示依頼なしに変更しない。

CIのJob、権限、Runner、必須Checkの段階的な有効化は `ci-strategy.md` に従う。新しいCheckは `main` で一度成功し、安定して再実行できることを確認してから必須化する。

## 緊急修正と取り消し

- 緊急修正も最新の `main` から `fix/<説明>` を作り、通常のPull Requestと必要な回帰テストを経由する。
- 常設の `hotfix` ブランチは作らない。
- `main` がビルド不能、起動不能、個人データを損失する状態になった場合は、新機能よりrevertまたは最小修正を優先する。
- 取り消し後に原因を再現するテストを追加し、安全を確認してから改めて実装する。
- 秘密情報をpushした場合は、コミット削除だけで解決扱いにせず、資格情報の失効・再発行と公開範囲の確認を行う。

## リリースとタグ

- `release` ブランチは作らず、検証済みの `main` のコミットだけをリリース候補にする。
- 意味のある動作確認済みの節目へ、Semantic Versioning形式の注釈付きタグを付ける。例: `v0.1.0`。
- タグを移動・上書きしない。誤ったタグは削除理由を記録し、新しい版を付ける。
- アプリのMarketing VersionとGitタグを合わせ、Build NumberはCIまたはXcodeのビルドごとに単調増加させる。
- 実機・現地検証が未完了の版をMVP完成版としてタグ付けしない。必要なら `v0.1.0-alpha.1` 等のプレリリースとして区別する。

タグ作成とリモートへのpushは外部状態を変更するため、ユーザーの明示依頼なしに実行しない。

## AIエージェントのGit操作

- 作業開始時に現在のブランチ、`git status`、関係する最近の履歴を読み取り、ユーザーの未コミット変更を保護する。
- ユーザーが明示的に依頼しない限り、ブランチ作成・切替・削除、commit、push、Pull Request作成、merge、rebase、reset、tagを実行しない。
- ユーザーの変更を勝手にstash、破棄、別ブランチへ移動しない。
- コミットを依頼された場合も、対象差分とテスト結果を確認し、無関係なファイルを含めない。
- push、Pull Request、マージ、保護規則変更、タグpushの前に、依頼範囲と対象リポジトリを確認する。
- `git reset --hard`、未確認対象への `git clean`、`main` へのforce pushを使用しない。

## Gitへ含めないもの

- `.DS_Store`、Xcodeの個人設定、DerivedData、ビルド成果物。
- APIキー、`.env`、WeatherKit等の認証・署名情報、Provisioning Profile。
- 個人のメモ、正確な位置履歴、未匿名化の診断ログ、カメラ映像。
- 生成済みの大容量オフラインパック。配布方法とGit LFSの採否を別途決定する。
- 一時ファイル、テスト結果バンドル、ローカルだけで使用するデバッグ出力。

秘密情報や個人データを `.gitignore` だけに頼って保護しない。生成元と保存先を設計し、コミット前の差分確認を必須にする。

## 公式参考資料

- [GitHub Docs: GitHub flow](https://docs.github.com/en/get-started/using-github/github-flow)
- [GitHub Docs: About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [GitHub Docs: Configuring commit squashing for pull requests](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/configuring-commit-squashing-for-pull-requests)
