# YamaLens オフラインパック生成

このツールは、開発用Macで取得済みの国土地理院標高タイルを、YamaLensの署名付き詳細オフラインパックへ変換する。パック生成とネットワーク取得を分離し、入力原本、利用条件、取得日を作業者が確認した後に実行する。

## 前提

- macOS、Python 3、OpenSSL 3を使用する。
- 標高入力は国土地理院の256×256 PNGまたはテキスト標高タイルとする。
- 入力ディレクトリは `z/x/y.png` または `z/x/y.txt` 構成にする。同じデータ種別・座標へ両形式を重複配置しない。
- データ種別は `DEM5A`、`DEM5B`、`DEM5C`、`DEM10B` のいずれかとする。
- 署名秘密鍵はリポジトリ外に置く。秘密鍵のバックアップとアクセス制御は別途運用する。
- 生成物と原本は `Data/Generated/` 等のGit追跡外領域へ置く。

実入力を取得したら、`Data/SourceManifests/gsi-dem-tanzawa-v1.yaml` の取得日、元データ更新日、座標系、入力ファイル、利用手続確認結果を更新する。未確認のまま本番配布用パックとして扱わない。

## 0. 正式な開発用原本を取得する

YamaLensの初期取得範囲は次の多解像度構成とする。

- 丹沢詳細域: 北緯35.30〜35.60度、東経138.95〜139.30度。DEM5A、DEM5B、DEM5Cをズーム15（約4m）、欠損補完用DEM10Bをズーム14（約8m）で取得する。
- 周辺粗地形: 北緯34.75〜35.95度、東経138.62〜139.33度。富士山、箱根、奥多摩、大菩薩、伊豆方面までの見通し確認用としてDEM10Bをズーム11（約62m）で取得する。

まず、追跡対象外の取得計画を生成する。

```sh
python3 Tools/OfflinePackageBuilder/acquire_gsi_tiles.py plan \
  --config Data/OfflinePackages/tanzawa-dem-acquisition-v1.json \
  --output Data/Generated/GSI/tanzawa-dem-acquisition-v1.json
```

生成結果は3,700件のURLになる。内訳とURLが想定どおりであることを確認後、明示操作で取得する。国土地理院の標高タイルは公開HTTPS URLから取得するため、基盤地図情報ダウンロードサービスのID・パスワードは使用しない。

```sh
python3 Tools/OfflinePackageBuilder/acquire_gsi_tiles.py fetch \
  --plan Data/Generated/GSI/tanzawa-dem-acquisition-v1.json \
  --destination Data/Generated/GSI
```

取得は並列化せず、既定でリクエスト間を0.2秒空ける。提供範囲外の404は `acquisition-inventory.json` の `unavailable` に記録する。取得済みの正常ファイルは再利用し、異常な既存ファイルや途中ファイルを自動上書きしない。

この取得物は、開発・容量測定・現地試験の正式原本として扱える。ただし商用配布用パックへ進める前に、地理院タイルの保存・加工・再配布形態について測量法上の申請要否を確認し、Source Manifestの利用手続欄を確定する。

## 1. 入力索引を作る

各データ種別を別ディレクトリへ保存した後、取得した種別だけ指定する。

```sh
python3 Tools/OfflinePackageBuilder/build_detailed_pack.py index \
  --source DEM5A=Data/Generated/GSI/DEM5A \
  --source DEM5B=Data/Generated/GSI/DEM5B \
  --source DEM5C=Data/Generated/GSI/DEM5C \
  --source DEM10B=Data/Generated/GSI/DEM10B \
  --output Data/Generated/tanzawa-detailed-v1/terrain-index.json
```

索引には、タイル座標、データ種別、入力ファイルへの相対パス、SHA-256が記録される。生成後に原本が変わった場合はビルドを拒否する。

同じズーム15のタイル・セルに複数の値がある場合はDEM5A、DEM5B、DEM5Cの順で最初の有効値を採用する。欠損が残り、対応するズーム14の親DEM10Bタイルが索引にある場合は、そのセルを2×2の最近傍展開で補完する。DEM10Bタイル自体も低解像度タイルとしてパックへ保持する。

1. DEM5A
2. DEM5B
3. DEM5C
4. 親タイルのDEM10B

## 2. 開発用署名鍵を用意する

次は例であり、出力先にはリポジトリ外のアクセス制限された場所を指定する。

```sh
openssl genpkey -algorithm Ed25519 -out /path/outside/repository/yamalens-pack-development.pem
```

アプリのCryptoKitへ登録する32byte公開鍵は次のコマンドで取り出せる。秘密鍵は出力されない。

```sh
python3 Tools/OfflinePackageBuilder/build_detailed_pack.py public-key \
  --private-key /path/outside/repository/yamalens-pack-development.pem \
  --output /tmp/yamalens-pack-development-public.raw
```

本番鍵を採用する場合は、先に公開鍵と `keyID` をアプリへ含めてアプリを配布し、その後に対応する秘密鍵でパックを署名する。

## 3. 詳細パックを生成する

```sh
python3 Tools/OfflinePackageBuilder/build_detailed_pack.py build \
  --config Data/OfflinePackages/tanzawa-detailed-v1.json \
  --terrain-index Data/Generated/tanzawa-detailed-v1/terrain-index.json \
  --private-key /path/outside/repository/yamalens-pack-development.pem \
  --output Data/Generated/tanzawa-detailed-v1/package
```

出力は次の4ファイルである。

```text
package/
├─ manifest.json
├─ manifest.sig
├─ catalog.sqlite
└─ terrain.lzfse
```

既存の出力ディレクトリは自動上書きしない。途中で失敗した場合は完成パックを残さず、次をすべて満たした場合だけ出力先へ切り替える。

- 入力ファイルのSHA-256一致
- 256行×256列、有限な標高値、Int16範囲
- 設定された対象範囲内のタイル
- LZFSE圧縮・展開の往復一致
- SQLiteの整合性・外部キー検査
- 地形offset、サイズ、展開後SHA-256の一致
- Ed25519署名生成と公開鍵による再検証

## 4. 開発ビルドへ詳細パックを同梱する

生成済みパックを、Debugビルドだけが参照するGit追跡外のResourceへ複製する。

```sh
Tools/OfflinePackageBuilder/stage_development_pack.sh
```

その後Xcodeからアプリをビルドし、「マイ」→「オフラインパック」→「丹沢詳細パックを保存」の順に操作する。同梱パックも通常の配布パックと同じ署名、SHA-256、SQLite、地形タイル検証を通過した場合だけ導入される。

- 同梱先は `YamaLens/YamaLens/Resources/DevelopmentOfflinePackages/` で、Gitには追跡しない。
- 秘密鍵やDEM原本はアプリへ同梱しない。
- Releaseビルドでは開発用ローカル導入コードを有効にしない。
- 再生成後は、スクリプトをもう一度実行して同梱ファイルを更新する。

## 5. 自動テスト

```sh
python3 Tools/OfflinePackageBuilder/test_build_detailed_pack.py -v
python3 Tools/OfflinePackageBuilder/test_acquire_gsi_tiles.py -v
```

テストは公開可能な固定標高値と一時的なEd25519鍵だけを使用し、実ネットワークや本番鍵へ依存しない。
