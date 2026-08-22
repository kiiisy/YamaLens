# YamaLens オフラインパック生成

このツールは、開発用Macで取得済みの国土地理院標高タイルを、YamaLensの署名付き詳細オフラインパックへ変換する。ネットワークからの一括取得は行わず、入力原本、利用条件、取得日を作業者が確認した後に実行する。

## 前提

- macOS、Python 3、OpenSSL 3を使用する。
- 標高入力は国土地理院の256×256テキスト標高タイルとする。
- 入力ディレクトリは `z/x/y.txt` 構成にする。
- データ種別は `DEM5A`、`DEM5B`、`DEM5C`、`DEM10B` のいずれかとする。
- 署名秘密鍵はリポジトリ外に置く。秘密鍵のバックアップとアクセス制御は別途運用する。
- 生成物と原本は `Data/Generated/` 等のGit追跡外領域へ置く。

実入力を取得したら、`Data/SourceManifests/gsi-dem-tanzawa-v1.yaml` の取得日、元データ更新日、座標系、入力ファイル、利用手続確認結果を更新する。未確認のまま本番配布用パックとして扱わない。

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

## 4. 自動テスト

```sh
python3 Tools/OfflinePackageBuilder/test_build_detailed_pack.py -v
```

テストは公開可能な固定標高値と一時的なEd25519鍵だけを使用し、実ネットワークや本番鍵へ依存しない。
