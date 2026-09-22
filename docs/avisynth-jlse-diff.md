# avisynth-jlse.Dockerfile の変更差分まとめ

`epgstation/avisynth-jlse.Dockerfile` は、次の2つを1本のマルチステージDockerfileにマージしたもの。
ビルドコンテキストは `epgstation/`（`docker-compose-sample.yml` の規約と同じ）。

- [tobitti0/Docker-AviSynthplus](https://github.com/tobitti0/Docker-AviSynthplus) の
  `8.0/ubuntu24.04/Dockerfile`（Ubuntu 24.04 + FFmpeg 8.0 + AviSynth+ v3.7.5 + L-SMASH-Works）
- JLSE（[tobitti0/JoinLogoScpTrialSetLinux](https://github.com/tobitti0/JoinLogoScpTrialSetLinux)）と
  EPGStation v2.10.0 のビルド手順

検証は Mac（Apple Silicon、Docker Desktop）で `nekojarashih1/epgstation:u2404`
（Docker-AviSynthplusの8.0/ubuntu24.04を先にビルドしておいたローカルイメージ）をベースに行った
（`~/TV-Recording/temp/mac-build/`）。基準値（無音区間・CMカット区間・チャプター・フレーム数など）は
Ubuntu 20.04版（`nekojarashih1/epgstation:5.1test`）および本番機haumeaのjlseと完全に一致することを
確認済み。ロゴ検出・delogoも、一致するロゴファイルがあれば正しく動作することを確認済み。

## stage 1〜2（avisynth-builder / avisynth-runtime）: 無改変

`tobitti0/Docker-AviSynthplus` の `8.0/ubuntu24.04/Dockerfile` と `avisynth/` 配下の補助スクリプト
（`build_source.sh` / `download_tarballs.sh` / `generate-source-of-truth-ffmpeg-versions.py` /
`install_ffmpeg.sh`）は、ステージ名を `builder`→`avisynth-builder`、`runtime`→`avisynth-runtime`
に変えた以外は無改変。`COPY` の参照パスを `avisynth/*.sh` に合わせて変更している。

## stage 3〜4（jlse-build / release）: temp/Dockerfile（2025-10-28版）からの変更点

元になった `~/TV-Recording/temp/Dockerfile` から、動作確認の過程で次を変更した。

### 1. 足りない実行時ライブラリの追加

`ubuntu:24.04` の最小イメージ（`avisynth-runtime`）には、ffmpeg・AviSynthプラグインが必要とする
共有ライブラリの一部（apt由来のランタイムパッケージ）が入っていない。`release` ステージで
以下をaptインストールする:

```
ca-certificates libasound2t64 libass9 libbrotli1 libdav1d7 libdrm2 libexpat1 libfribidi0
libgomp1 libharfbuzz0b libnuma1 libpng16-16t64 libsndio7.0 libva-drm2 libva-x11-2 libva2
libvdpau1 libx11-6 libxcb-shape0 libxcb-shm0 libxcb-xfixes0 libxcb1 libxext6 libxml2 libxv1
```

これが無いと `ffmpeg` 自体が `libdrm.so.2: cannot open shared object file` 等で起動しない。

### 2. AviSynth+ ヘッダーの追加

`avisynth-runtime` には実行時ライブラリ（`libavisynth.so`）だけでヘッダーが入っていない。
`logoframe` / `libdelogo.so` のビルドに `avisynth.h` が必要なため、`jlse-build` ステージで
同じタグ（`v3.7.5`）から改めて `git clone` してヘッダーだけ `/usr/local/include/avisynth/` に置く。

### 3. `apt-get purge` から `python3` を除外（重要なバグ修正）

EPGStationのビルド後、ビルド専用パッケージ（`python3 make g++`）を削除して掃除する処理があるが、
**`python3` を含めて purge すると `nodejs` まで巻き込まれて削除される**。

原因: NodeSource版 `nodejs` パッケージが `python3` に依存（Depends）しており、`libboost-*-dev`
パッケージ経由で `python3` が自動インストールされる → `apt-get purge python3 ...` は
`python3` に依存している `nodejs` も強制的に削除対象にする（`--auto-remove` の話ではなく、
依存関係の充足が壊れるための強制削除）。

再現していた症状: ビルドは最後まで通るが、スモークテストの `jlse --help` が
`/usr/bin/env: 'node': No such file or directory` で失敗する。

対応: `apt-get purge -y --auto-remove make g++` として `python3` を対象から外した。

### 4. JLSE本体（`join_logo_scp_trial/src/jlse.js`）への `cachefile` パッチ（重要なバグ修正）

JLSEが生成するAviSynthスクリプト（`in_org.avs`）は、映像用 `LWLibavVideoSource` と音声用
`LWLibavAudioSource` の両方を同じTSファイルに対して開く。デフォルトでは両者が同じキャッシュ
インデックスファイル（`<TSファイル名>.lwi`）を共有する。

**この組み合わせで、L-SMASH-Works（`liblsmashsource.so`）の `parse_index()` が確実にセグフォルト
する不具合を確認した**（gdbでスタックトレースを取得: `parse_index` → `lwlibav_construct_index`
→ `LWLibavAudioSource::LWLibavAudioSource` → クラッシュ）。新規作成・既存キャッシュの再利用の
どちらでも再現し、`ffmpeg`/`ffprobe` 単体で同じ `.avs` を開かせても同じ場所で落ちるため、
JLSE固有の問題ではなくAviSynthのインデックス共有処理自体の問題と見られる
（FFmpeg 8.0自体やAviSynth+ v3.7.5自体の互換性問題ではない。原因の完全な特定はしていない）。

映像用・音声用に **別々の `cachefile` オプション**を指定すると、新規作成・再利用のどちらでも
再現しなくなることを確認した。そのため `jlse-build` ステージで、cloneした
`join_logo_scp_trial/src/jlse.js` の `createAvs` 関数にsedパッチを当てている:

```js
// 変更前
LWLibavVideoSource(TSFilePath, repeat=true, dominance=1)
AudioDub(last,LWLibavAudioSource(TSFilePath, stream_index=${index}, av_sync=true))

// 変更後
LWLibavVideoSource(TSFilePath, repeat=true, dominance=1, cachefile=TSFilePath+".video.lwi")
AudioDub(last,LWLibavAudioSource(TSFilePath, stream_index=${index}, av_sync=true, cachefile=TSFilePath+".audio.lwi"))
```

`chapter_exe` の `compat.h` への `<cstdint>` 追加パッチ（gcc 13向け）は、元のDockerfileから
そのまま引き継いでいる（変更なし）。

### 5. スモークテストの追加

ビルドの最後に、ffmpeg起動・avisynth入力フォーマットの確認・共有ライブラリの未解決参照が
無いことの確認・JLSE各バイナリと `libdelogo.so` の存在確認・`jlse --help` を実行し、
壊れたイメージがそのまま完成扱いにならないようにしている。

## 未検証・今後の課題

- このマージ後のDockerfileそのものを、ゼロからのフルビルドではまだ通していない
  （検証は `nekojarashih1/epgstation:u2404` という既存のローカルイメージをベースにした
  等価な構成で行った）。フルビルドは数十分〜数時間かかる見込み。
- ロゴ検出・delogoは、一致するロゴファイル（`.lgd`）がある場合に正しく動作することを確認したが、
  本番で使っている全ロゴでの網羅的な確認はしていない。
- `epgstation/config/config.yml.template` 等の既存の設定テンプレートは、このリポジトリが
  もともと想定している `l3tnun/epgstation` の最新版（master）向けのもの。EPGStation v2.10.0の
  設定項目と完全に一致するとは限らないため、`avisynth-jlse.Dockerfile` を使う場合は
  ビルドしたイメージの `/app/config/config.yml.template` を基準にすることを推奨する。
