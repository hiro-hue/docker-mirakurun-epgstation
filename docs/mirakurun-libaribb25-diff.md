# Mirakurun (libaribb25/softcas後継) の取り込みについて

`mirakurun/src` は、自前フォーク [hiro-hue/Mirakurun](https://github.com/hiro-hue/Mirakurun)
（**private**）を指す git submodule（ブランチ `mirakurun-4.1.3-libaribb25`、本番稼働中のコミット
`6638500` にピン留め）。upstream の [Chinachu/Mirakurun](https://github.com/Chinachu/Mirakurun)
4.1.3 をベースに、B-CASカードリーダーなしでB25復号を行うため
[libyakisoba](https://github.com/tsunoda14/libyakisoba) /
[libsobacas](https://github.com/tsunoda14/libsobacas) /
[libaribb25（tsukumijima fork）](https://github.com/tsukumijima/libaribb25)
を組み込んでいる（旧softcas自前実装からの移行。経緯は submodule 内の `SOFTCAS.md` を参照）。

## なぜ submodule なのか（重要: 秘密情報の扱い）

`hiro-hue/Mirakurun` には `bcas_keys`（B-CAS復号鍵、ビルド時に既定値として焼き込まれる）が
含まれている。このリポジトリ（`docker-mirakurun-epgstation` のfork）は **public** なので、
鍵の実体が公開履歴に紛れ込まないよう、ソースをコピーするのではなく **private repoへの
git submodule参照（コミットSHAのみ）** にしている。

- `git submodule update --init` には `hiro-hue/Mirakurun` への読み取り権限（SSHキー等）が必要。
  権限が無い場合はビルドできない（意図的な制限）。
- 鍵をイメージに焼き込まず、ホスト側ファイルの差し替えだけで更新したい場合は、環境変数
  `BCAS_KEYS_FILE`（例: `/app-config/bcas_keys` にマウントしたファイルを指す）を使う。
  本番（haumea）ではこの方式に切り替え済み。詳細は submodule 内の `SOFTCAS.md` を参照。
- **鍵の値は、このリポジトリはもちろん、vaultやドキュメントのどこにも書かない。**

## ビルド・起動

`docker-compose-avisynth-jlse-sample.yml` の `mirakurun` サービスを参照。

```sh
git submodule update --init mirakurun/src
docker compose -f docker-compose-avisynth-jlse-sample.yml build mirakurun
docker compose -f docker-compose-avisynth-jlse-sample.yml up -d mirakurun
```

`network_mode: host` / `device_cgroup_rules` / `tmpfs: /tmp` は、submodule内の
`docker/docker-compose.yml`（upstream側のサンプル）の設定に合わせている。ボリュームパスは、
このリポジトリの既存の規約（`./mirakurun/conf`、`./mirakurun/data` 相対パス）に合わせて変更した
（upstream側サンプルは `/opt/mirakurun/...` の絶対パスを使っているが、これは本番機haumea固有の
配置なので採用していない）。

## 未検証

- この `docker-compose-avisynth-jlse-sample.yml` 経由でのビルド・起動そのものはまだ確認していない
  （本番での動作確認は、submoduleとは別の環境・手順で実施済み。詳細はvaultの設計ログ
  `2026-09-21_mirakurun-4.1.3-upgrade.md` / `2026-09-21_mirakurun-softcas-libaribb25移行.md`）。
