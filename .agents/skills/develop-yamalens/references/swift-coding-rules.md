# YamaLens Swiftコーディング規則

この文書は、YamaLensのSwiftコードを実装・レビューするときに適用する。Swiftの文法上可能かどうかではなく、仕様との対応、読みやすさ、安全性、テストのしやすさを優先する。

## 目次

1. 基本方針
2. 名前とファイル
3. 値と型の扱い
4. Optionalとエラー
5. 並行処理
6. SwiftUI
7. アーキテクチャと依存関係
8. セキュリティ、ログ、プライバシー
9. テスト
10. コメントと未完了コード
11. レビュー用早見表
12. 公式参考資料
13. 比較に使用したスタイルガイド

## 1. 基本方針

- Swift 6言語モードと完全な並行性チェックを前提にする。コンパイラー警告を放置せず、警告を無効化して回避しない。
- コードの短さより、呼び出し箇所で意味が明確であることを優先する。
- `let` を既定とし、値を変更する必要がある場合だけ `var` を使用する。
- アクセスレベルは最小にする。ファイル内だけで使う宣言には `private`、モジュール外へ公開しない宣言には既定の `internal` を使用する。
- Xcodeの標準フォーマットを使用する。タブを使わず、インデントはスペース4個とする。1行が長く読みにくい場合は引数やモディファイアーを1行ずつ分ける。
- セミコロンを使用せず、原則として1行に1つの文を書く。
- 配列、辞書、引数などを複数行へ分ける場合は、各要素を1行ずつ書き、最後の要素にも末尾カンマを付ける。要素追加時の差分を小さく保つ。
- 使用するトップレベルモジュールだけを明示的に `import` し、推移的なimportに依存しない。importはアルファベット順に並べる。
- 本番コードに、強制アンラップ、強制キャスト、強制的なエラー無視を残さない。
- ビルドを通すためだけのダミー値、空の成功処理、握りつぶしたエラーを作らない。

## 2. 名前とファイル

### 命名

- 型、プロトコル、列挙型には `UpperCamelCase` を使用する。例: `MountainCandidate`、`WeatherFreshness`。
- 関数、プロパティ、変数、列挙ケースには `lowerCamelCase` を使用する。例: `rankCandidates`、`retrievedAt`。
- 識別子は英語で記述し、ユーザー向け文言は日本語のローカライズリソースへ置く。
- 略語を独自に作らない。一般的な略語はSwiftの大文字・小文字規則に合わせる。例: `sourceURL`、`mountainID`、`gpsAccuracy`。
- Bool値は疑問として読める名前にする。例: `isOffline`、`hasSavedPackage`、`canUseCamera`。
- 関数名は処理内容が読める動詞から始める。例: `loadMountains()`、`calculateBearing(to:)`。
- 型名を変数名へそのまま繰り返さず、役割を表す。`mountainData` より `selectedMountain`、`date` より `retrievedAt` を優先する。
- `Manager`、`Helper`、`Util`、`Common` のように責務が曖昧な名前を避ける。`OfflinePackageStore`、`CandidateRanker` のように役割を示す。

```swift
// 良い例
let selectedMountain: Mountain
let retrievedAt: Date
func calculateBearing(to destination: Coordinate) -> Angle

// 避ける例
let mountainData: Mountain
let date: Date
func calc(_ value: Coordinate) -> Double
```

### ファイル

- 1ファイルにつき、原則として中心となる型を1つ置き、ファイル名を型名と一致させる。
- 既存型へプロトコル適合だけを追加するファイルは、`型名+プロトコル名.swift` とする。例: `Mountain+Identifiable.swift`。
- 小さな関連型、`private`な補助型、同じ型の拡張は同じファイルへ置いてよい。
- 巨大なSwiftUIビューを、単に行数ではなく「独立した表示責務」「独立した状態」「再利用可能な部品」を基準に分割する。
- ファイル内は、中心となる型、関連するイニシャライザー、公開または内部API、`private`実装、拡張の順で読みやすく並べる。

## 3. 値と型の扱い

- ドメインモデルと計算入力には、可能な限り `struct` と不変の値を使用する。参照共有が必要な場合だけ `class` または `actor` を使用する。
- 意味の異なる値を、すべて生の `Double` や `String` で表さない。緯度経度、距離、方位、仰角、精度、標高、情報鮮度を型で区別する。
- 角度が度かラジアンか、距離がメートルかキロメートルかを、型名または `Measurement`／`Angle` で明示する。
- 時刻は表示文字列ではなく `Date` として保持し、表示時に `FormatStyle` で整形する。
- 状態の組み合わせを複数のBool値で表さず、取り得る状態を列挙型で表現する。
- ドメイン上不正な値を作りにくいイニシャライザーを用意する。入力境界で検証し、内部では検証済みの値を扱う。

```swift
enum DataFreshness: Equatable, Sendable {
    case current(retrievedAt: Date)
    case stale(retrievedAt: Date)
    case unavailable(reason: UnavailableReason)
}

// `isLoading`、`hasError`、`hasData` の組み合わせより、状態を一意にする。
enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)
}
```

## 4. Optionalとエラー

- `Optional` は「値が存在しないことが正しい状態」を表す場合に使用する。設計不足を隠すために何でもOptionalにしない。
- 本番コードで `!`、`try!`、`as!` を使用しない。テスト固定データで使用する場合も、失敗理由が分かる `#require` などを優先する。
- `guard` を使い、前提を満たさない経路を早く終了させる。深いネストを避ける。
- `try?` でエラーを捨てない。値がなくても問題ないと仕様上明確な場合だけ使用し、その理由をコメントする。
- 未取得の気温、距離、風速、精度などを `0` で代用しない。`nil`、状態列挙型、または明示的なエラーとして扱う。
- 下位層では原因を保持した型付きエラーを返し、UI境界で日本語の表示状態へ変換する。
- ユーザーへ技術的なエラー文字列をそのまま表示しない。理由、利用可能な代替、再試行や設定への導線を示す。
- エラーは事前決定事項13.6節の5分類と再試行可否へ変換する。フレームワーク固有エラーやHTTP状態だけでUIを分岐させない。
- すべてのエラーを共通処理で自動再試行しない。署名・ハッシュ不一致、未対応schema、SQLite破損、権限拒否、容量不足は一時的な通信失敗と区別する。

```swift
guard let location else {
    return .unavailable(reason: .locationNotAvailable)
}

// 避ける: 未取得を海抜0mとして計算してしまう。
let altitude = location?.altitude ?? 0
```

## 5. 並行処理

- 非同期処理には `async`／`await` を使用する。新規コードでコールバックの多段ネストを作らない。
- UI状態を変更する型・処理を `@MainActor` へ隔離する。重い計算やファイル処理をMainActor上で実行しない。
- 共有される可変状態は、値型で不変にするか、所有者を1つにするか、`actor` で保護する。
- 並行処理の境界をまたぐ値型は `Sendable` に適合させる。`@unchecked Sendable` は原則禁止とし、やむを得ない場合は安全性の根拠とテストを記録する。
- `Task.detached` を原則使用しない。親タスクのキャンセル、優先度、Actor文脈を引き継ぐ通常の `Task` または構造化並行処理を使用する。
- 長時間処理、ダウンロード、候補算出ループではキャンセルを確認し、画面離脱や新しい要求で古い結果を反映しない。
- `DispatchQueue` を新規のアプリロジックへ直接使用しない。Appleフレームワークのコールバックを橋渡しするアダプター内に限定する。
- 並行性エラーを `@preconcurrency` や `nonisolated(unsafe)` で安易に抑制しない。

## 6. SwiftUI

- Liquid Glassを含む画面・ナビゲーション・操作部品は [liquid-glass-ui-rules.md](liquid-glass-ui-rules.md) に従う。
- `body` はUIの宣言に限定し、ネットワーク、データベース、センサー開始、重い計算を実行しない。
- 一時的でビュー自身が所有する状態には `@State private` を使用する。
- 親が所有する値を子が編集する場合だけ `@Binding` を使用する。読み取りだけなら通常の値として渡す。
- 共有される参照モデルはObservationの `@Observable` を基本とし、所有者と単一の正本を明確にする。
- 単純な状態のために形式だけの `ScreenModel` を作らない。複数の非同期処理、キャンセル、状態遷移をViewから分離して検証する価値がある場合に使用する。
- 複数画面または意味のあるView階層で共有する状態だけをEnvironmentへ置き、所有者を一つにする。Environmentをサービスロケーターとして使用しない。
- ビューからグローバルなシングルトンへ直接アクセスしない。
- 非同期の画面処理には `.task` または `.task(id:)` を使用し、SwiftUIによるキャンセルに対応する。
- `body` 内で同じ条件分岐や長いレイアウトが繰り返される場合は、意味のある小さなビューへ抽出する。
- 配色、余白、文字スタイルを各画面へ直書きせず、YamaLensのデザイントークンまたは共通コンポーネントを使用する。
- `TabView`、`NavigationStack`、ツールバー、検索、Menu、sheet、alert等の標準部品を優先し、Liquid Glassを模倣する独自material・blur・shadowの組み合わせを作らない。
- ユーザー向け文字列を連結して文章を作らない。ローカライズ可能な完全な文として定義する。
- 画面を追加・変更したら、通常、空、エラー、オフライン、権限拒否、Dynamic Type拡大のうち関係するプレビューを追加する。

## 7. アーキテクチャと依存関係

- ファイルとターゲットの配置は `project-structure.md` に従う。
- 依存方向を `UI → アプリケーション／ドメイン ← データ・端末アダプター` とし、ドメイン層からSwiftUI、SwiftData、WeatherKit、Core Location、AVFoundationを参照しない。
- プロトコルは、実装型の都合ではなく利用側が必要とする最小の操作として定義する。
- 依存関係はイニシャライザーで注入する。グローバル変数や変更可能なシングルトンを使用しない。
- ネットワーク、時刻、位置情報、永続化、センサーは、テストで固定値へ置き換えられるようにする。
- 機能間で型を共有する必要がある場合は、最初にドメイン上の意味を確認する。便利だからという理由だけで `Common` フォルダーへ移さない。
- 外部パッケージを追加する前に、Apple標準機能で実現できない理由、保守状況、ライセンス、アプリ容量、プライバシーへの影響を記録し、ユーザーの承認を得る。
- SwiftLintやSwiftFormatは現時点では追加しない。まずXcode標準フォーマットとコンパイラー警告を使用し、自動化が必要になった時点で別途決定する。

## 8. セキュリティ、ログ、プライバシー

- ログには `Logger`（OSLog）を使用し、`print` を本番コードへ残さない。
- 正確な緯度経度、位置履歴、メモ本文、検索語、カメラ映像、外部URLの個人情報部分を通常ログへ出力しない。
- ログへ値を含める場合は、公開・非公開の指定を明示する。診断に不要な値は記録しない。
- エラーを記録する場合も、ユーザーデータではなく処理名、状態、匿名化された識別子、エラー分類を優先する。
- 開発用診断ログはユーザーの明示操作でのみ保存し、内容確認後に共有できるようにする。
- 通信はHTTPSとApp Transport Securityの標準設定を使用し、`NSAllowsArbitraryLoads`、例外ドメイン、独自の証明書信頼処理を追加しない。
- URLは文字列連結せず `URLComponents` またはフレームワークの型で構築する。外部URLは許可したscheme、ユーザー情報の不在、長さを検証してから開く。
- ネットワーク、manifest、SQLite、地形タイル等の外部入力を信頼しない。サイズ、件数、文字列長、offset、展開後サイズを検証し、入力由来の値を無制限なメモリ確保やSQLとして使用しない。
- SwiftData、診断ログ、パック、キャッシュへ、事前決定事項13.8節のFile Protectionとバックアップ属性を設定する。SwiftDataはWALとSHMを含めて確認する。
- 秘密情報が将来必要になった場合だけKeychainへ保存する。`UserDefaults`、ソースコード、ログ、Fixtureへ秘密情報を置かない。
- `PrivacyInfo.xcprivacy` は実際のRequired Reason API利用と一致させる。推測の理由コードを追加せず、APIを追加・変更した箇所と同じ変更で更新する。
- 診断ログの30日・20件上限、保持指定、匿名化共有、正確な位置を含む共有の追加確認、共有一時ファイルの削除を一つのライフサイクルとして実装する。

## 9. テスト

- テストの種類、固定入力、実行範囲、証拠は `testing-strategy.md` に従う。
- 新しいユニットテストと結合テストにはSwift Testingを使用する。UI操作テストにはXCTest／XCUIAutomationを使用する。
- テスト名は、条件と期待結果が分かる日本語または明確な英語にする。
- 1テストでは1つの動作を検証し、失敗時に何が壊れたか判断できるようにする。
- 正常系だけでなく、境界値、欠損、権限拒否、キャンセル、オフライン、古い情報、破損データを検証する。
- 距離、方位、仰角、画角判定にはパラメーター化テストを使用し、北の0度境界や単位変換を含める。
- `Date.now`、現在地、ネットワーク、実センサーへ直接依存するテストを作らない。Clock、位置、サービス、保存先を注入して固定する。
- テスト間で可変のグローバル状態を共有しない。実行順序や並列実行に依存させない。
- バグ修正では、修正前に失敗する最小の回帰テストを追加してから修正する。

```swift
import Testing

struct BearingDifferenceCase: Sendable {
    let heading: Double
    let bearing: Double
    let expected: Double
}

@Test(
    "方位差を北の境界をまたいで正規化する",
    arguments: [
        BearingDifferenceCase(heading: 359, bearing: 1, expected: 2),
        BearingDifferenceCase(heading: 1, bearing: 359, expected: -2),
    ]
)
func normalizesBearingDifference(_ testCase: BearingDifferenceCase) {
    let actual = bearingDifference(
        from: testCase.heading,
        to: testCase.bearing
    )

    #expect(actual == testCase.expected)
}
```

## 10. コメントと未完了コード

- コメントには、コードから分かる「何をしているか」ではなく、判断理由、単位、仕様上の制約、回避できない技術的事情を書く。
- ドメイン上重要な型・関数と、誤用しやすい内部APIには `///` のドキュメントコメントを付ける。
- コメントアウトしたコードを残さない。不要なコードは削除し、履歴はGitへ任せる。
- `TODO` を残す場合は、未完了の内容と理由を具体的に書く。仮実装を完成扱いにしない。
- `fatalError()`、`preconditionFailure()`、空の `catch` を通常の実行経路へ残さない。開発時限定の場合はコンパイル条件と理由を明示する。

```swift
// 良い例: 地磁気の一時的な乱れを候補なしと誤認しないため、直近3件を平滑化する。

// 避ける例: 方位を計算する。
```

## 11. レビュー用早見表

- 名前だけで役割・単位・時刻の意味が分かるか。
- `!`、`try!`、`as!`、握りつぶしたエラー、未取得値の `0` 置換がないか。
- `body` にI/Oや重い計算がないか。
- UI以外のロジックを固定入力でテストできるか。
- UI更新はMainActor、共有可変状態はActorまたは単一所有者で守られているか。
- タスクのキャンセル後に古い結果を画面へ反映しないか。
- 位置、メモ、カメラ、検索語をログへ出していないか。
- ATS例外、未検証URL、入力由来の無制限なサイズ・offset・SQL、誤ったFile Protectionがないか。
- Privacy Manifestが実際のAPI利用と一致し、診断ログが明示操作・保持上限・共有確認・削除方針に従っているか。
- 仕様上の失敗・オフライン・権限拒否を状態として扱っているか。
- 新しい外部依存、グローバル状態、責務が曖昧な型を増やしていないか。
- 変更した動作を証明するテストまたはプレビューがあるか。
- Liquid Glassが操作レイヤーへ限定され、標準部品とアクセシビリティ設定へ追従しているか。

## 12. 公式参考資料

- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- [The Swift Programming Language: Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Apple Developer Documentation: SwiftUI Model data](https://developer.apple.com/documentation/SwiftUI/Model-data)
- [Apple Developer Documentation: Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass)
- [Apple Developer Documentation: Swift Testing](https://developer.apple.com/documentation/Testing)
- [Apple Developer Documentation: Testing in Xcode](https://developer.apple.com/documentation/xcode/testing)

## 13. 比較に使用したスタイルガイド

次の資料は規則を比較・補完するために使用する。内容が競合する場合は、このYamaLensコーディング規則を優先する。

- [Zenn: Swift Style Guide リンク集](https://zenn.dev/503/articles/f329d1292afc27)
- [Google Swift Style Guide](https://google.github.io/swift/)
- [Airbnb Swift Style Guide](https://github.com/airbnb/swift)
- [Kodeco Swift Style Guide](https://github.com/kodecocodes/swift-style-guide)
- [LinkedIn Swift Style Guide](https://github.com/linkedin/swift-style-guide)
