# YamaLensプロジェクト配置規則

この文書は、Xcodeプロジェクトの作成、ファイルの追加・移動、アーキテクチャ変更で使用する。設計判断の正本は `doc/YamaLens_事前決定事項.md` と `doc/YamaLens_基本設計書.md` 3章であり、この文書は実装時の配置判断を補助する。

## 目次

1. 採用方式
2. 依存方向
3. 各フォルダーへ置くもの
4. 配置の判断手順
5. ScreenModelの境界
6. Environmentの境界
7. ターゲットとテスト配置
8. 実行時の保存場所
9. 新しい境界を増やす条件
10. 参考資料

## 採用方式

- 機能単位のレイヤードアーキテクチャを使用する。
- SwiftUI画面は状態の複雑さに応じて `View` 単独または `View` と `ScreenModel` で構成する。これは必要な画面内ではMVVMに近いが、1画面1ViewModelを規則にせず、アプリ全体を巨大なViewModelで管理しない。
- UIKitのView Controllerを中心とするMVCは使用しない。
- TCA等の外部アーキテクチャライブラリは、正本文書を更新して採用理由を記録しない限り追加しない。
- MVP開始時は単一アプリターゲットとし、フォルダーで境界を守る。将来利用するかもしれないという理由だけでモジュールを分割しない。
- XcodeプロジェクトはBundle Identifier `com.kiiisy.YamaLens`、Deployment Target iOS 26.0、Swift 6、Automatic Signingで作成する。Apple Developer Teamは共有設定へ固定しない。

## 依存方向

```text
FeaturesのView
    ↓ 操作と描画
FeaturesのScreenModel
    ↓
Domainの値・サービス・Repositoryプロトコル
    ↑ 実装
Infrastructureのアダプター

AppのComposition Rootだけが具象実装を組み立てる
```

- `Domain` から `Features`、`Infrastructure`、`DesignSystem`、AppleのUI・端末・保存フレームワークをimportしない。
- `Features` からInfrastructureの具象型を直接生成・参照しない。
- 別Featureの内部型を直接参照しない。共有が必要なら、ドメイン概念、共通UI、画面遷移のどれかを判断して適切な場所へ移す。
- 依存関係はイニシャライザーで渡す。SwiftUI Environmentは、Appで組み立てた画面横断の依存を配る用途に限定する。

## 各フォルダーへ置くもの

| 場所 | 置くもの | 例 |
| --- | --- | --- |
| `App/` | アプリ起動、`AppContainer`、ルートタブ、画面遷移 | `YamaLensApp.swift`、`AppContainer.swift`、`AppRoute.swift` |
| `Features/<機能>/` | 画面、必要な場合の `ScreenModel`、画面状態、画面固有部品 | `HomeView.swift`、`HomeScreenModel.swift`、`HomeState.swift` |
| `Domain/Models/` | フレームワーク非依存のドメイン値 | `Mountain.swift`、`UserMountainState.swift` |
| `Domain/CandidateIdentification/` | 距離、方位、仰角、候補順位付けの純粋ロジック | `CandidateRanker.swift` |
| `Domain/Repositories/` | 利用側が必要とする最小のデータ操作プロトコル | `MountainRepository.swift` |
| `Domain/Services/` | 複数のドメイン処理を意味のある単位で調整する処理 | `MountainSearchService.swift` |
| `Infrastructure/Persistence/` | SwiftDataによる個人データ保存 | `SwiftDataUserMountainStateRepository.swift` |
| `Infrastructure/OfflinePackages/` | 読み取り専用SQLite、LZFSE地形、署名・ハッシュ検証、置換 | `SQLiteMountainRepository.swift` |
| `Infrastructure/Weather/` | WeatherKitの現在・予報・前日サマリーと各キャッシュ | `WeatherKitWeatherRepository.swift`、`PreviousDayWeatherSummaryRepository.swift` |
| `Infrastructure/Sensors/` | Core Location、Core Motionの取得と正規化 | `CoreLocationObservationProvider.swift` |
| `Infrastructure/Camera/` | AVFoundationのセッションと画角情報 | `CameraSessionAdapter.swift` |
| `Infrastructure/Network/` | URLSessionによるダウンロード | `OfflinePackageDownloader.swift` |
| `Infrastructure/Diagnostics/` | 明示保存する診断ログ、匿名化、共有、保持期限 | `DiagnosticLogStore.swift` |
| `Infrastructure/ExternalMaps/` | MapKitの駅検索、Apple Maps／Google Mapsへの外部遷移 | `MapKitStationSearch.swift`、`ExternalMapLauncher.swift` |
| `DesignSystem/` | 色、文字、余白、再利用する見た目 | `YamaColor.swift`、`FreshnessBadge.swift` |
| `Resources/` | Asset Catalog、ローカライズ文字列、Privacy Manifest、同梱する軽量データ | `Assets.xcassets`、`Localizable.xcstrings`、`PrivacyInfo.xcprivacy`、`Bootstrap/bootstrap.sqlite` |
| `Tools/OfflinePackageBuilder/` | アプリへ含めないパック生成・検証ツール | 変換処理、マニフェスト生成 |
| `Scripts/CI/` | ローカルとGitHub Actionsで共用する決定的な検証処理 | `validate-repository.sh` |
| `Data/SourceManifests/` | データ出典、利用条件、取得・確認日 | `tanzawa-sources.yaml` |

## 配置の判断手順

1. ユーザーへ見える一つの機能だけで使うか確認し、該当するなら `Features/<機能>` に置く。
2. UIやAppleフレームワークなしで意味を持つ山・候補・鮮度等の概念なら `Domain` に置く。
3. 保存、通信、センサー、カメラ、外部アプリ等との接続なら `Infrastructure` に置く。
4. 複数画面で同じ見た目を再利用するなら `DesignSystem` に置く。
5. 起動時の組み立てまたはアプリ全体の遷移なら `App` に置く。
6. 当てはまらない場合も `Common`、`Manager`、`Helper` を新設せず、責務を具体的に命名する。

## ScreenModelの境界

- Viewだけで完結する表示切り替え、フォーカス、入力途中の値には `@State` を使用し、形式だけの `ScreenModel` を作らない。
- 複数の非同期処理、キャンセル、読み込み・空・失敗等の状態遷移を持ち、Viewから分離してテストする価値がある場合に作る。
- `@MainActor` とObservationの `@Observable` を基本とする。
- 画面に必要な状態を保持し、ユーザー操作を受け、Domainの処理を呼び出す。
- SwiftUIのView型、SwiftDataのModelContext、AVCaptureSession、CLLocationManager等を保持しない。
- 距離・方位・候補順位等の再利用可能な計算を実装しない。
- 画面離脱や入力変更時に非同期処理をキャンセルし、古い結果を反映しない。

## Environmentの境界

- 複数画面または意味のあるView階層で同じ正本を共有する状態に使用する。
- 状態の所有者を注入元に一つだけ置き、子Viewが同じデータの複製を持たないようにする。
- 画面固有の状態をアプリ全体へ公開しない。
- すべてのRepositoryやServiceを取得するサービスロケーターとして使用しない。具象依存は `AppContainer` で組み立て、必要な境界へ明示的に渡す。

## ターゲットとテスト配置

- テストの種類と必須ケースは `testing-strategy.md` に従う。
- `YamaLens`: 本番アプリ。App、Features、Domain、Infrastructure、DesignSystem、Resourcesを含める。
- `YamaLensTests`: Swift TestingによるDomain、ScreenModel、Infrastructure境界のユニット・結合テストを、対象と対応するサブフォルダーへ置く。
- `YamaLensUITests`: XCTest／XCUIAutomationによる重要導線のUI操作テストを置く。
- 小さな固定データ、センサーリプレイ、スタブは `YamaLensTests/Support` に置き、本番ターゲットへ含めない。
- 大容量の生成済みパックは、配布方法とGit LFSの採否を決めるまでGitへ登録しない。
- オフラインパックの生成物は `Data/Generated/` に置いてGit追跡せず、出典と生成条件だけを `Data/SourceManifests/` へ登録する。

## 実行時の保存場所

| 端末内の場所 | 内容 | 保護・バックアップ |
| --- | --- | --- |
| App Bundle | `bootstrap.sqlite`、`PrivacyInfo.xcprivacy`、公開鍵 | 読み取り専用。ビルド署名で保護する |
| Application Support/UserData | SwiftDataストア、WAL、SHM。メモ、お気に入り、よく使う出発駅を含む | `NSFileProtectionComplete`、通常バックアップ対象 |
| Application Support/OfflinePackages | 検証済みパック、導入ジャーナル、一時領域 | `NSFileProtectionCompleteUntilFirstUserAuthentication`、バックアップ対象外 |
| Application Support/Diagnostics | 明示保存した診断ログ | `NSFileProtectionComplete`、バックアップ対象外 |
| Caches/Weather | WeatherKitの現在・予報・前日サマリーキャッシュ | `NSFileProtectionCompleteUntilFirstUserAuthentication`、OSによる削除を許容 |
| tmp/DiagnosticExports | 共有用一時ファイル | `NSFileProtectionComplete`、共有後または24時間以内に削除 |

- 保存先URLは一つの保存場所定義から生成し、FeatureやViewへ生のパスを散在させない。
- ディレクトリ作成時にFile Protectionとバックアップ除外属性を設定し、既存ディレクトリを再利用する場合も期待属性を検証・補正する。
- パック更新、キャッシュ削除、診断ログ削除、個人データ初期化を別操作として実装し、異なる保存領域を一括削除しない。

## 新しい境界を増やす条件

次のいずれかをテストまたは実測で確認した場合だけ、Swift PackageやFrameworkへの分割を検討する。

- Domainだけを高速にビルド・テストする必要がある。
- 複数ターゲットから同じ実装を利用する必要がある。
- 誤った依存をフォルダー規則だけでは継続的に防げない。

分割時は、ビルド時間、循環依存、公開API、テスト、リソース配置への影響を記録し、基本設計書を同時に更新する。

## 参考資料

- [Apple Developer Documentation: Model data](https://developer.apple.com/documentation/swiftui/model-data)
- [Apple Developer Documentation: Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [Apple Developer Documentation: ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer)
- [Zenn: ViewModelを使わない、SwiftUIらしいiOSアーキテクチャ](https://zenn.dev/kyoichi/articles/47a5e019b0a75d)
- [Qiita: SwiftUI時代のアーキテクチャ選定](https://qiita.com/Zack-yutapon/items/16f0019806b56ff091ad)

外部記事は比較材料として使用し、YamaLensの正本にはしない。特にSPMの多パッケージ分割、1画面1ViewModel、すべての処理をUseCaseにする構成は、実測された必要性が生じた場合だけ採用する。
