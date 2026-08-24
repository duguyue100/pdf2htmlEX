FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        pkg-config \
        git \
        python3 \
        curl ca-certificates xz-utils \
        libcairo2-dev \
        libfreetype-dev \
        libfontconfig1-dev \
        libjpeg-dev libpng-dev libgif-dev libtiff-dev \
        libopenjp2-7-dev \
        liblcms2-dev \
        libspiro-dev libxml2-dev libzstd-dev \
        zlib1g-dev gettext libboost-dev \
    && rm -rf /var/lib/apt/lists/*

# ---- poppler (static, internal headers exported) --------------------------
ARG POPPLER_VERSION=24.01.0
RUN curl -LfsS "https://poppler.freedesktop.org/poppler-${POPPLER_VERSION}.tar.xz" -o /tmp/pp.tar.xz \
    && mkdir /tmp/pp && tar -xJf /tmp/pp.tar.xz --strip-components=1 -C /tmp/pp \
    && mkdir -p /tmp/pp/test \
    && cmake -S /tmp/pp -B /tmp/pp/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_UNSTABLE_API_ABI_HEADERS=ON \
        -DFONT_CONFIGURATION=fontconfig \
        -DENABLE_GLIB=OFF \
        -DENABLE_CPP=OFF \
        -DENABLE_QT5=OFF \
        -DENABLE_QT6=OFF \
        -DENABLE_UTILS=OFF \
        -DENABLE_LIBOPENJPEG=openjpeg2 \
        -DENABLE_CMS=lcms2 \
        -DENABLE_LIBCURL=OFF \
        -DENABLE_NSS3=OFF \
        -DENABLE_GPGME=OFF \
    && cmake --build /tmp/pp/build -j"$(nproc)" \
    && cmake --install /tmp/pp/build \
    && mv /tmp/pp /opt/poppler-src

# ---- fontforge (static; headers are not installed by upstream) ------------
ARG FONTFORGE_VERSION=20230101
RUN curl -LfsS "https://github.com/fontforge/fontforge/archive/refs/tags/${FONTFORGE_VERSION}.tar.gz" -o /tmp/ff.tar.gz \
    && mkdir /tmp/ff && tar -xzf /tmp/ff.tar.gz --strip-components=1 -C /tmp/ff \
    && sed -i 's/add_custom_target(pofiles ALL/add_custom_target(pofiles/' /tmp/ff/po/CMakeLists.txt \
    && cmake -S /tmp/ff -B /tmp/ff/build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_GUI=OFF \
        -DENABLE_X11=OFF \
        -DENABLE_PYTHON_SCRIPTING=OFF \
        -DENABLE_NATIVE_SCRIPTING=ON \
        -DENABLE_DOCS=OFF \
    && cmake --build /tmp/ff/build -j"$(nproc)" \
    && cmake --build /tmp/ff/build --target pofiles \
    && cmake --install /tmp/ff/build \
    && cp /tmp/ff/build/lib/libfontforge.a /usr/local/lib/ \
    && mkdir -p /usr/local/include/fontforge \
    && cp /tmp/ff/inc/*.h /tmp/ff/fontforge/*.h /tmp/ff/build/inc/*.h /usr/local/include/fontforge/ \
    && rm -rf /tmp/ff /tmp/ff.tar.gz

# ---- pdf2htmlEX ------------------------------------------------------------
WORKDIR /src
COPY . /src

RUN cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DPOPPLER_STATIC=/usr/local/lib/libpoppler.a \
        -DFONTFORGE_STATIC=/usr/local/lib/libfontforge.a \
        -DPOPPLER_SOURCE_DIR=/opt/poppler-src \
    && cmake --build build -j"$(nproc)" \
    && cmake --install build --prefix /usr/local

# smoke test: convert a PDF, verify HTML output contains the text
RUN cd /tmp && /usr/local/bin/pdf2htmlEX /src/test/data/smoke.pdf smoke.html; \
    test -s smoke.html && grep -q "Hello pdf2htmlEX revived" smoke.html && echo "SMOKE TEST PASSED"
