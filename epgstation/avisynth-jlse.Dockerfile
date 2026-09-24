# EPGStation v2.10.0 + JLSE (CMカット/チャプター生成) を、Ubuntu 24.04 / FFmpeg 8.0 / AviSynth+ v3.7.5 の上に
# ゼロから自己完結でビルドする（外部の非公開ベースイメージに依存しない）。
#
# 出典・マージ元:
#   1. tobitti0/Docker-AviSynthplus の 8.0/ubuntu24.04/Dockerfile（stage: avisynth-builder / avisynth-runtime）
#      https://github.com/tobitti0/Docker-AviSynthplus/tree/master/8.0/ubuntu24.04
#      FFmpeg 8.0 + AviSynth+ v3.7.5 + L-SMASH-Works（Mr-Ojii版フォーク）をソースからビルドする部分は、
#      このファイルの改変なしに使っている（avisynth/ 配下の補助スクリプトも同じ）。
#   2. JLSE（tobitti0/JoinLogoScpTrialSetLinux）+ EPGStation v2.10.0 のビルド（stage: jlse-build / release）
#      これは、mac上での動作確認（~/TV-Recording/temp/mac-build/Dockerfile.2404）で得た知見を反映している。
#      オリジナル（temp/Dockerfile、2025-10-28版）からの変更点は次の3点（詳細はこのリポジトリのdocs参照）:
#        a. u2404相当のベースに足りない実行時ライブラリをaptで追加（AviSynthプラグイン・ffmpeg用）
#        b. EPGStationビルド後の後片付けで `python3` を purge しない
#           （NodeSource版nodejsがpython3に依存しており、purgeするとnodejsも道連れで消えてffmpeg/JLSEが
#           動かなくなる不具合があった）
#        c. JLSE本体（join_logo_scp_trial の src/jlse.js）に、生成するavsスクリプトの
#           LWLibavVideoSource / LWLibavAudioSource それぞれに別々の cachefile を指定するパッチを追加
#           （同じキャッシュファイルを共有すると、L-SMASH-Worksのインデックス解析でセグフォルトする
#            不具合をgdbで確認した。詳細はdocs/avisynth-jlse-diff.md）
#      最後にスモークテスト（ffmpeg起動・avisynth入力・各バイナリの存在・jlse --help）を入れ、
#      壊れたイメージが完成扱いにならないようにしている。
#
# ビルドコンテキストは "epgstation/"（docker-compose-sample.yml と同じ規約）。
# avisynth/ 配下の *.sh, *.py は Docker-AviSynthplus からそのままコピーしたもの（無改変）。

# ============================================================
# stage 1: avisynth-builder — FFmpeg 8.0 + AviSynth+ v3.7.5 + L-SMASH-Works をソースからビルド
#          （tobitti0/Docker-AviSynthplus の 8.0/ubuntu24.04/Dockerfile と同一内容）
# ============================================================
FROM       ubuntu:24.04 AS avisynth-builder

WORKDIR     /tmp/workdir

COPY avisynth/generate-source-of-truth-ffmpeg-versions.py /tmp/workdir
COPY avisynth/download_tarballs.sh /tmp/workdir
COPY avisynth/build_source.sh /tmp/workdir
COPY avisynth/install_ffmpeg.sh /tmp/workdir


ENV FFMPEG_VERSION=8.0

## ------add ------
ENV AVISYNTHPLUS_VERSION=v3.7.5
ENV XXHASH_VERSION=v0.8.3
ENV OBUPARSE_VERSION=v2.0.1
ENV LSMASH_VERSION=315b4747d759e336ef30b18e93f2e676810e5a73
ENV LSMASHSOURCE_VERSION=0eda0054bc1fede95370f0759b5d6734670d9f41

# Add Package
# AviSynthPlus  - https://github.com/AviSynth/AviSynthPlus
# xxhash        - https://github.com/Cyan4973/xxHash
# obuparse      - https://github.com/dwbuiten/obuparse
# l-smash       - https://github.com/Mr-Ojii/l-smash
# L-SMASH-Works - https://github.com/Mr-Ojii/L-SMASH-Works

## ------add end ------

# fribidi
ARG FRIBIDI_PKGS="libfribidi-dev libfribidi0"
# libass
ARG LIBASS_PKGS="libass-dev libass9"
# xorg-macros
ARG XORG_MACROS_PKGS="libxcb-shm0-dev libxcb-shm0 libxcb-xfixes0 libxcb-xfixes0-dev"
# libxau
ARG XAU_PKGS="libxau-dev libxau6"
# libpthread-stubs
ARG PTHREADS_STUBS_PKGS="libpthread-stubs0-dev"
# libxml2 ( started giving me download problems, so I went back to the debian package's version )
ARG XML2_PKGS="libxml2-dev libxml2"
# libpng
ARG PNG_PKGS="libpng-dev libpng16-16t64"

ENV MAKEFLAGS="-j2"
ENV PKG_CONFIG_PATH="/opt/ffmpeg/share/pkgconfig:/opt/ffmpeg/lib/pkgconfig:/opt/ffmpeg/lib64/pkgconfig:/opt/ffmpeg/lib/x86_64-linux-gnu/pkgconfig:/opt/ffmpeg/lib/aarch64-linux-gnu/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig"

ENV PREFIX="/opt/ffmpeg"
ENV LD_LIBRARY_PATH="/opt/ffmpeg/lib:/opt/ffmpeg/lib64:/opt/ffmpeg/lib/aarch64-linux-gnu"


ARG DEBIAN_FRONTEND=noninteractive

RUN     apt-get -yqq update && \
        apt-get install -yq --no-install-recommends curl jq python3 python3-requests less tree file vim

RUN      buildDeps="autoconf \
                    automake \
                    cmake \
                    build-essential \
                    texinfo \
                    curl \
                    wget \
                    tar \
                    bzip2 \
                    libexpat1-dev \
                    gcc \
                    git \
                    git-core \
                    gperf \
                    libtool \
                    make \
                    meson \
                    ninja-build \
                    nasm \
                    perl \
                    pkg-config \
                    python3 \
                    yasm \
                    zlib1g-dev \
                    libfreetype6-dev \
                    libgnutls28-dev \
                    libsdl2-dev \
                    libva-dev \
                    libvdpau-dev \
                    libnuma-dev \
                    libdav1d-dev \
                    openssl \
                    libssl-dev \
                    expat \
                    libgomp1" && \
        apt-get -yqq update && \
        apt-get install -yq --no-install-recommends ${buildDeps}

# Note: pass '--library-list' to 'generate-source-of-truth-ffmpeg-versions.py'
#       ex: '--library-list lib1,lib2,lib3'
#  for more control over the build process, and how the docker layers are cached

# RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list libopencore-amr,libx264,libx265,libogg,libopus,libvorbis,libvpx,libwebp,libmp3lame,libxvid,libfdk-aac,openjpeg,freetype,libvidstab,fribidi,fontconfig,libass,kvazaar,aom,libsvtav1,xorg-macros,xproto,libxau,libpthread-stubs,libxml2,libbluray,libzmq,libpng,libaribb24,zimg,libtheora,libsrt,libvmaf,ffmpeg
# dont do this 👆 where all of the libs are built at one time.
# by splitting them up into batches we allow docker to cache the layers ( which is a lifesaver when debugging )
# I left this line in here, as it shows the proper order of the libraries that need to be built. ( what worked )
# there are only a few build deps. I remember that libtheora needed libogg.

RUN \
        echo "Installing dependencies..." && \
        apt-get install -yq --no-install-recommends ${FRIBIDI_PKGS} ${LIBASS_PKGS} ${XORG_MACROS_PKGS} ${XAU_PKGS} ${XML2_PKGS} ${PNG_PKGS}
# apt-get install -yq --no-install-recommends ${FRIBIDI_PKGS} ${LIBASS_PKGS} ${XORG_MACROS_PKGS} ${XAU_PKGS} ${PTHREADS_STUBS_PKGS} ${XML2_PKGS} ${PNG_PKGS}


# First batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list libopencore-amr,libx264,libx265,libogg,libopus
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh


#  additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list libvorbis,libvpx,libwebp,libmp3lame
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

# additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list libxvid,libpthread-stubs
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

# additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list libfdk-aac,openjpeg,freetype,libvidstab
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

# additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list fontconfig
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

# additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list kvazaar
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

# additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list aom,libsvtav1
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

# additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list xproto
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh


# additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list libbluray,libzmq
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

# additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list libaribb24,zimg,libtheora
# Note: libtheora is dependant on libogg
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

# additional batch of libraries ( split into docker layers, to allow for caching )
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list libsrt,libvmaf,whisper
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

## ------add ------
# AviSynth+ (build and install)
RUN     set -xe && \
        DIR=/tmp/avisynth && \
        mkdir -p ${DIR} && \
        cd ${DIR} && \
        git clone --depth 1 -b ${AVISYNTHPLUS_VERSION} https://github.com/AviSynth/AviSynthPlus.git && \
        cd AviSynthPlus && \
        mkdir avisynth-build && \
        cd avisynth-build && \
        cmake ../ -G Ninja -DCMAKE_INSTALL_PREFIX=${PREFIX} && \
        ninja && \
        ninja install && \
        ldconfig && \
        rm -rf ${DIR}
## ------add end ------

# This is a slow one, put it on its own container layer to speed up the build (allowing it to be cached)
RUN /tmp/workdir/generate-source-of-truth-ffmpeg-versions.py --library-list ffmpeg-8.0
## when  debugging you can pass in || true to the end of the next 3 commands
## to keep the build going even if one of the steps fails
RUN /tmp/workdir/download_tarballs.sh
RUN /tmp/workdir/build_source.sh

## ------add ------
# L-smash dependencies: xxHash (build and install)
RUN set -xe && \
    DIR=/tmp/xxhash && \
    mkdir -p ${DIR} && \
    cd ${DIR} && \
    git init && \
    git remote add origin https://github.com/Cyan4973/xxHash.git && \
    git fetch origin && \
    git checkout ${XXHASH_VERSION} && \
    make PREFIX="${PREFIX}" && \
    make install PREFIX="${PREFIX}" && \
    rm -rf ${DIR}

# L-smash dependencies: obuparse (build and install)
RUN set -xe && \
    DIR=/tmp/obuparse && \
    mkdir -p ${DIR} && \
    cd ${DIR} && \
    git init && \
    git remote add origin https://github.com/dwbuiten/obuparse.git && \
    git fetch origin && \
    git checkout ${OBUPARSE_VERSION} && \
    make PREFIX="${PREFIX}" && \
    make install PREFIX="${PREFIX}" && \
    rm -rf ${DIR}

# l-smash (build and install)
RUN set -xe && \
    DIR=/tmp/l-smash && \
    mkdir -p ${DIR} && \
    cd ${DIR} && \
    git init && \
    git remote add origin https://github.com/Mr-Ojii/l-smash.git && \
    git fetch origin && \
    git checkout ${LSMASH_VERSION} && \
    ./configure --extra-cflags="-I${PREFIX}/include" --extra-ldflags="-L${PREFIX}/lib -L${PREFIX}/lib64" --enable-shared --prefix="${PREFIX}" && \
    make && \
    make install && \
    ldconfig && \
    rm -rf ${DIR}

# L-SMASH-Works (build and install)
# lsmash-works-mpeg2-progressive-field.patch: MPEG-2 の progressive_frame（ソフトテレシネ部分）で、
# FFmpeg のパーサーが top_field_first を返さないため直前のフィールド情報を使い回してしまい、
# RFF の次のコマでフィールド順が食い違ったと判定されて repeat=true がファイル全体で無効になる不具合の修正。
# （上流 Mr-Ojii/L-SMASH-Works の master でも未修正。詳細は docs/avisynth-jlse-diff.md）
COPY avisynth/lsmash-works-mpeg2-progressive-field.patch /tmp/workdir/
RUN set -xe && \
    DIR=/tmp/l-smash-works && \
    mkdir -p ${DIR} && \
    cd ${DIR} && \
    git init && \
    git remote add origin https://github.com/Mr-Ojii/L-SMASH-Works.git && \
    git fetch origin && \
    git checkout ${LSMASHSOURCE_VERSION} && \
    git apply /tmp/workdir/lsmash-works-mpeg2-progressive-field.patch && \
    grep -q "AV_FIELD_PROGRESSIVE" common/lwindex.c && \
    cd AviSynth && \
    LDFLAGS="-Wl,-Bsymbolic" meson setup build  --prefix "${PREFIX}" && \
    cd build && \
    ninja && \
    ninja install && \
    ldconfig && \
    rm -rf ${DIR}

## Avisynth (copy lib and plugins)
RUN cp ${PREFIX}/lib/libavisynth.so* /usr/local/lib/
RUN cp -r ${PREFIX}/lib/avisynth /usr/local/lib

## L-SMASH-works (copy the dependencies to the lib)
RUN ldd ${PREFIX}/lib/avisynth/liblsmashsource.so | grep opt/ffmpeg | cut -d ' ' -f 3 | xargs -i cp {} /usr/local/lib/

## ------add end ------

RUN /tmp/workdir/install_ffmpeg.sh


# ============================================================
# stage 2: avisynth-runtime — 実行に必要なものだけを持つ最小イメージ
#          （tobitti0/Docker-AviSynthplus の runtime stage と同一内容。旧タグ "u2404" 相当）
# ============================================================
FROM ubuntu:24.04 AS avisynth-runtime

# Copy fonts and fontconfig from builder
COPY --from=avisynth-builder /usr/share/fonts /usr/share/fonts
COPY --from=avisynth-builder /usr/share/fontconfig /usr/share/fontconfig
COPY --from=avisynth-builder /usr/bin/fc-* /usr/bin/

# Copy rest of the content
COPY --from=avisynth-builder /usr/local /usr/local/

LABEL       org.opencontainers.image.authors="tobitti0" \
            org.opencontainers.image.source=https://github.com/tobitti0/Docker-AviSynthplus/

ENV         LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64

CMD         ["--help"]
ENTRYPOINT  ["ffmpeg"]


# ============================================================
# stage 3: jlse-build — JLSE（join_logo_scp_trial）と EPGStation v2.10.0 をビルド
# ============================================================
FROM avisynth-runtime AS jlse-build

ENV DEBIAN_FRONTEND=noninteractive
ENV NODE_VERSION=20
ENV EPGSTATION_VERSION=v2.10.0

RUN set -xe && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
    curl git make gcc g++ cmake libboost-all-dev ca-certificates

# AviSynth+ のヘッダー（logoframe / delogo が -I/usr/local/include/avisynth で参照する）。
# avisynth-runtime には実行時ライブラリ(libavisynth.so)だけでヘッダーが無いので、
# stage 1 と同じタグ(v3.7.5)から改めて取得する（ヘッダーのみなのでビルドし直すより軽い）。
RUN set -xe && \
    git clone --depth 1 -b v3.7.5 https://github.com/AviSynth/AviSynthPlus.git /tmp/AviSynthPlus && \
    mkdir -p /usr/local/include/avisynth && \
    cp -r /tmp/AviSynthPlus/avs_core/include/* /usr/local/include/avisynth/ && \
    test -f /usr/local/include/avisynth/avisynth.h && \
    rm -rf /tmp/AviSynthPlus

# join_logo_scp_trial build
# サブモジュールは親リポジトリ(JoinLogoScpTrialSetLinux master)が固定しているコミットのまま使う
# （動作確認済みの組み合わせ。上流の最新masterへは上げない）。
# chapter_exeのcompat.hへの<cstdint>追加は、gcc 13でのビルドに必要なパッチ。
# jlse.js（in_org.avs生成）へのcachefileパッチ: L-SMASH-Worksで、LWLibavVideoSourceと
# LWLibavAudioSourceが既定のcachefile（TSファイル名+".lwi"）を共有すると、2つ目のソースを
# 開く際に共有インデックスの解析でセグフォルトする不具合がある（詳細は docs/avisynth-jlse-diff.md）。
# 双方に別々のcachefileを指定すると再現しないため、jlse.jsが生成するavsスクリプトに追加する。
RUN set -xe && \
    cd /tmp/ && \
    git clone --recursive https://github.com/tobitti0/JoinLogoScpTrialSetLinux.git && \
    cd /tmp/JoinLogoScpTrialSetLinux && \
    git submodule status && \
    cd /tmp/JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial && \
    sed -i 's/LWLibavVideoSource(TSFilePath, repeat=true, dominance=1)/LWLibavVideoSource(TSFilePath, repeat=true, dominance=1, cachefile=TSFilePath+".video.lwi")/' src/jlse.js && \
    sed -i 's/AudioDub(last,LWLibavAudioSource(TSFilePath, stream_index=${index}, av_sync=true))/AudioDub(last,LWLibavAudioSource(TSFilePath, stream_index=${index}, av_sync=true, cachefile=TSFilePath+".audio.lwi"))/' src/jlse.js && \
    grep -n "cachefile" src/jlse.js && \
    cd /tmp/JoinLogoScpTrialSetLinux/modules/chapter_exe && \
    sed -i '/#ifndef _WIN32/a #include <cstdint>' src/compat.h && \
    cd src && \
    make && \
    mv chapter_exe /tmp/JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial/bin/ && \
    cd /tmp/JoinLogoScpTrialSetLinux/modules/logoframe/src && \
    make && \
    mv logoframe /tmp/JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial/bin/ && \
    cd /tmp/JoinLogoScpTrialSetLinux/modules/join_logo_scp/src && \
    make && \
    mv join_logo_scp /tmp/JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial/bin/ && \
    cd /tmp/JoinLogoScpTrialSetLinux/modules/tsdivider/ && \
    mkdir build && \
    cd build && \
    cmake -DCMAKE_BUILD_TYPE=Release .. && \
    make && \
    mv tsdivider /tmp/JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial/bin/ && \
    mv /tmp/JoinLogoScpTrialSetLinux/modules/join_logo_scp_trial /join_logo_scp_trial

# delogo
RUN set -xe && \
    git clone https://github.com/tobitti0/delogo-AviSynthPlus-Linux && \
    cd delogo-AviSynthPlus-Linux/src && \
    make && \
    cp libdelogo.so /join_logo_scp_trial

# node setup tool
RUN set -xe && \
    curl -O -sL https://deb.nodesource.com/setup_${NODE_VERSION}.x && \
    mv setup_${NODE_VERSION}.x /join_logo_scp_trial/setup_node.x

# EPGStation clone
RUN set -xe && \
    cd /tmp && \
    git clone https://github.com/l3tnun/EPGStation.git -b ${EPGSTATION_VERSION}


# ============================================================
# stage 4: release — 配布イメージ本体
# ============================================================
FROM avisynth-runtime AS release
ENV DEBIAN_FRONTEND=noninteractive
LABEL org.opencontainers.image.description="EPGStation v2.10.0 + JLSE on Ubuntu 24.04 (FFmpeg 8.0 / AviSynth+ v3.7.5, self-contained build)"

# avisynth-runtime の ffmpeg/AviSynthプラグインが必要とする実行時ライブラリ
# （ubuntu:24.04 の最小イメージには入っていないため。04_find-missing-libs.sh 相当の調査結果）
RUN set -xe && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
    ca-certificates \
    libasound2t64 libass9 libbrotli1 libdav1d7 libdrm2 libexpat1 libfribidi0 libgomp1 libharfbuzz0b libnuma1 \
    libpng16-16t64 libsndio7.0 libva-drm2 libva-x11-2 libva2 libvdpau1 libx11-6 libxcb-shape0 libxcb-shm0 \
    libxcb-xfixes0 libxcb1 libxext6 libxml2 libxv1 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=jlse-build /join_logo_scp_trial /join_logo_scp_trial
COPY --from=jlse-build /tmp/EPGStation /app

WORKDIR /join_logo_scp_trial
RUN bash setup_node.x && \
    apt-get update && \
    apt-get install --no-install-recommends -y nodejs libboost-filesystem-dev libboost-program-options-dev libboost-system-dev && \
    node -v && \
    npm --version && \
    mv libdelogo.so /usr/local/lib/avisynth && \
    ls /usr/local/lib/avisynth && \
    npm install && \
    npm link && \
    jlse --help

# install EPGStation
# 注意: python3 は purge しない。NodeSource版nodejsがpython3に依存(Depends)しているため、
# 一緒にpurgeするとnodejsごと消えてffmpeg/JLSEの起動に必要なnodeが無くなる不具合があった。
RUN set -xe && \
    apt-get update && \
    apt-get install --no-install-recommends -y python3 make g++ && \
    cd /app && \
    npm install && \
    npm install async && \
    npm run all-install && \
    npm run build && \
    apt-get purge -y --auto-remove make g++ && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# スモークテスト（壊れたイメージを完成扱いにしない）
RUN set -xe && \
    ffmpeg -hide_banner -version | head -1 && \
    ffmpeg -hide_banner -formats | grep -i avisynth && \
    if ldd /usr/local/bin/ffmpeg | grep "not found"; then exit 1; fi && \
    for b in chapter_exe logoframe join_logo_scp tsdivider; do test -x /join_logo_scp_trial/bin/$b; done && \
    test -f /usr/local/lib/avisynth/libdelogo.so && \
    test -f /app/dist/index.js && \
    jlse --help > /dev/null

WORKDIR /app
ENTRYPOINT ["npm"]
CMD ["start"]
