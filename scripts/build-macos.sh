#!/usr/bin/env bash
# Build a fully static pdf2htmlEX for macOS arm64 (Apple Silicon).
#
# Mirrors Dockerfile.alpine-static: source-built poppler + fontforge +
# transitive deps, all linked statically into one self-contained binary.
# Designed to run on a GitHub Actions macos-14 (or any Apple Silicon) machine.
#
# Usage: scripts/build-macos.sh
# Result: dist/pdf2htmlEX-macos-arm64.tar.gz
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build-macos"
STAGE="$BUILD/staging"
SRC="$BUILD/src"
DIST="$ROOT/dist"
NPROC="$(sysctl -n hw.ncpu)"

export PKG_CONFIG_PATH="$STAGE/lib/pkgconfig"
export CMAKE_PREFIX_PATH="$STAGE"
mkdir -p "$STAGE" "$SRC" "$DIST"

fetch() {
    local url="$1"
    local f="$SRC/$(basename "$url")"
    [ -f "$f" ] || curl -LfsS "$url" -o "$f"
    echo "$f"
}

cmake_bi() { # cmake_bi <srcdir> [extra cmake args...]
    local src="$1"; shift
    cmake -S "$src" -B "$src/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$STAGE" \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_OSX_ARCHITECTURES="${ARCH:-arm64}" \
        "$@"
    cmake --build "$src/build" -j"$NPROC"
    cmake --install "$src/build"
}

meson_bi() { # meson_bi <srcdir> [extra meson args...]
    local src="$1"; shift
    meson setup "$src/build" "$src" --prefix="$STAGE" \
        --default-library=static --buildtype=release "$@"
    meson compile -C "$src/build" -j"$NPROC"
    meson install -C "$src/build"
}

command -v meson >/dev/null || {
    # PEP 668: system python is externally managed; use a private venv
    python3 -m venv "$BUILD/venv"
    "$BUILD/venv/bin/pip" install --quiet meson ninja
    export PATH="$BUILD/venv/bin:$PATH"
}

# ---- 1. zlib ---------------------------------------------------------------
[ -d "$SRC/zlib" ] || {
    f=$(fetch https://zlib.net/fossils/zlib-1.3.1.tar.gz)
    mkdir "$SRC/zlib" && tar -xzf "$f" --strip-components=1 -C "$SRC/zlib"
}
if [ ! -f "$STAGE/lib/libz.a" ]; then
    (cd "$SRC/zlib" && ./configure --static --prefix="$STAGE" >/dev/null \
        && make -j"$NPROC" >/dev/null && make install >/dev/null)
fi

# ---- 2. libpng -------------------------------------------------------------
[ -d "$SRC/libpng" ] || {
    f=$(fetch https://downloads.sourceforge.net/project/libpng/libpng16/1.6.43/libpng-1.6.43.tar.xz)
    mkdir "$SRC/libpng" && tar -xJf "$f" --strip-components=1 -C "$SRC/libpng"
}
[ -f "$STAGE/lib/libpng16.a" ] || cmake_bi "$SRC/libpng" -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_FRAMEWORK=OFF

# ---- 3. libjpeg-turbo ------------------------------------------------------
[ -d "$SRC/jpeg" ] || {
    f=$(fetch https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/3.0.2.tar.gz)
    mkdir "$SRC/jpeg" && tar -xzf "$f" --strip-components=1 -C "$SRC/jpeg"
}
[ -f "$STAGE/lib/libjpeg.a" ] || cmake_bi "$SRC/jpeg" -DENABLE_SHARED=OFF -DENABLE_STATIC=ON

# ---- 4. expat --------------------------------------------------------------
[ -d "$SRC/expat" ] || {
    f=$(fetch https://github.com/libexpat/libexpat/releases/download/R_2_6_2/expat-2.6.2.tar.xz)
    mkdir "$SRC/expat" && tar -xJf "$f" --strip-components=1 -C "$SRC/expat"
}
[ -f "$STAGE/lib/libexpat.a" ] || cmake_bi "$SRC/expat" -DEXPAT_BUILD_DOCS=OFF -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_SHARED_LIBS=OFF

# ---- 5. pcre2 (for glib) ---------------------------------------------------
[ -d "$SRC/pcre2" ] || {
    f=$(fetch https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.bz2)
    mkdir "$SRC/pcre2" && tar -xjf "$f" --strip-components=1 -C "$SRC/pcre2"
}
[ -f "$STAGE/lib/libpcre2-8.a" ] || cmake_bi "$SRC/pcre2" -DPCRE2_BUILD_TESTS=OFF -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_SUPPORT_UNICODE=ON

# ---- 6. libffi (for glib) --------------------------------------------------
[ -d "$SRC/libffi" ] || {
    f=$(fetch https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz)
    mkdir "$SRC/libffi" && tar -xzf "$f" --strip-components=1 -C "$SRC/libffi"
}
if [ ! -f "$STAGE/lib/libffi.a" ]; then
    (cd "$SRC/libffi" && ./configure --prefix="$STAGE" --enable-static --disable-shared >/dev/null \
        && make -j"$NPROC" >/dev/null && make install >/dev/null)
fi

# ---- 7. glib ---------------------------------------------------------------
[ -d "$SRC/glib" ] || {
    f=$(fetch https://download.gnome.org/sources/glib/2.80/glib-2.80.0.tar.xz)
    mkdir "$SRC/glib" && tar -xJf "$f" --strip-components=1 -C "$SRC/glib"
}
[ -f "$STAGE/lib/libglib-2.0.a" ] || meson_bi "$SRC/glib" \
    -Dnls=disabled -Dintrospection=disabled -Ddocumentation=false -Dman-pages=disabled \
    -Dtests=false -Dinstalled_tests=false -Dlibmount=disabled -Dselinux=disabled \
    -Dsysprof=disabled -Dglib_debug=disabled -Dglib_assert=false

# ---- 8. pixman (for cairo) -------------------------------------------------
[ -d "$SRC/pixman" ] || {
    f=$(fetch https://cairographics.org/snapshots/pixman-0.43.4.tar.gz)
    mkdir "$SRC/pixman" && tar -xzf "$f" --strip-components=1 -C "$SRC/pixman"
}
[ -f "$STAGE/lib/libpixman-1.a" ] || meson_bi "$SRC/pixman" -Dgtk=disabled -Dtests=disabled -Ddemos=disabled -Dlibpng=disabled

# ---- 9. freetype -----------------------------------------------------------
[ -d "$SRC/freetype" ] || {
    f=$(fetch https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.xz)
    mkdir "$SRC/freetype" && tar -xJf "$f" --strip-components=1 -C "$SRC/freetype"
}
[ -f "$STAGE/lib/libfreetype.a" ] || cmake_bi "$SRC/freetype" \
    -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON -DFT_DISABLE_BZIP2=ON \
    -DFT_DISABLE_ZLIB=ON -DFT_DISABLE_PNG=ON

# ---- 10. fontconfig --------------------------------------------------------
[ -d "$SRC/fontconfig" ] || {
    f=$(fetch https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.15.0.tar.xz)
    mkdir "$SRC/fontconfig" && tar -xJf "$f" --strip-components=1 -C "$SRC/fontconfig"
}
[ -f "$STAGE/lib/libfontconfig.a" ] || meson_bi "$SRC/fontconfig" \
    -Ddoc=disabled -Dtests=disabled -Dtools=disabled

# ---- 11. cairo -------------------------------------------------------------
[ -d "$SRC/cairo" ] || {
    f=$(fetch https://cairographics.org/releases/cairo-1.18.0.tar.xz)
    mkdir "$SRC/cairo" && tar -xJf "$f" --strip-components=1 -C "$SRC/cairo"
}
[ -f "$STAGE/lib/libcairo.a" ] || meson_bi "$SRC/cairo" \
    -Dtests=disabled -Dxlib=disabled -Dxcb=disabled -Dspectre=disabled \
    -Dsymbol-lookup=disabled -Dgtk2-utils=disabled

# ---- 12. lcms2 (for poppler) ----------------------------------------------
[ -d "$SRC/lcms2" ] || {
    f=$(fetch https://github.com/mm2/Little-CMS/releases/download/lcms2.16/lcms2-2.16.tar.gz)
    mkdir "$SRC/lcms2" && tar -xzf "$f" --strip-components=1 -C "$SRC/lcms2"
}
[ -f "$STAGE/lib/liblcms2.a" ] || cmake_bi "$SRC/lcms2"

# ---- 13. poppler (static, internal headers exported) -----------------------
POPPLER_VERSION=24.01.0
[ -d "$SRC/poppler-src" ] || {
    f=$(fetch https://poppler.freedesktop.org/poppler-${POPPLER_VERSION}.tar.xz)
    mkdir "$SRC/poppler-src" && tar -xJf "$f" --strip-components=1 -C "$SRC/poppler-src"
}
[ -f "$STAGE/lib/libpoppler.a" ] || {
    mkdir -p "$SRC/poppler-src/test"
    cmake_bi "$SRC/poppler-src" \
        -DENABLE_UNSTABLE_API_ABI_HEADERS=ON \
        -DFONT_CONFIGURATION=fontconfig \
        -DENABLE_GLIB=OFF -DENABLE_CPP=OFF -DENABLE_QT5=OFF -DENABLE_QT6=OFF \
        -DENABLE_UTILS=OFF -DENABLE_LIBOPENJPEG=none -DENABLE_CMS=lcms2 \
        -DENABLE_LIBCURL=OFF -DENABLE_NSS3=OFF -DENABLE_GPGME=OFF \
        -DFREETYPE_LIBRARY="$STAGE/lib/libfreetype.a" \
        -DJPEG_LIBRARY="$STAGE/lib/libjpeg.a"
}

# ---- 14. fontforge (static) ------------------------------------------------
FONTFORGE_VERSION=20230101
[ -d "$SRC/fontforge" ] || {
    f=$(fetch https://github.com/fontforge/fontforge/archive/refs/tags/${FONTFORGE_VERSION}.tar.gz)
    mkdir "$SRC/fontforge" && tar -xzf "$f" --strip-components=1 -C "$SRC/fontforge"
}
[ -f "$STAGE/lib/libfontforge.a" ] || {
    sed -i.bak 's/add_custom_target(pofiles ALL/add_custom_target(pofiles/' "$SRC/fontforge/po/CMakeLists.txt"
    cmake_bi "$SRC/fontforge" \
        -DENABLE_GUI=OFF -DENABLE_X11=OFF -DENABLE_LIBSPIRO=OFF \
        -DENABLE_LIBTIFF=OFF -DENABLE_WOFF2=OFF \
        -DENABLE_PYTHON_SCRIPTING=OFF -DENABLE_NATIVE_SCRIPTING=ON \
        -DENABLE_DOCS=OFF \
        -DFREETYPE_LIBRARY="$STAGE/lib/libfreetype.a" \
        -DFREETYPE_INCLUDE_DIR="$STAGE/include/freetype2"
    cp "$SRC/fontforge/build/lib/libfontforge.a" "$STAGE/lib/"
    mkdir -p "$STAGE/include/fontforge"
    cp "$SRC"/fontforge/inc/*.h "$STAGE/include/fontforge/"
    cp "$SRC"/fontforge/fontforge/*.h "$STAGE/include/fontforge/"
    cp "$SRC"/fontforge/build/inc/*.h "$STAGE/include/fontforge/" 2>/dev/null || true
}

# ---- 15. pdf2htmlEX --------------------------------------------------------
cmake -S "$ROOT" -B "$BUILD/pdf2htmlex" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="${ARCH:-arm64}" \
    -DPOPPLER_STATIC="$STAGE/lib/libpoppler.a" \
    -DFONTFORGE_STATIC="$STAGE/lib/libfontforge.a" \
    -DPOPPLER_SOURCE_DIR="$SRC/poppler-src" \
    -DFREETYPE_LIBRARY="$STAGE/lib/libfreetype.a" \
    -DPDF2HTMLEX_TRANSITIVE_DEPS="fontconfig;libjpeg;libpng16;lcms2;gobject-2.0;gio-2.0" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$STAGE/lib"
cmake --build "$BUILD/pdf2htmlex" -j"$NPROC"

# ---- package + verify ------------------------------------------------------
BIN="$BUILD/pdf2htmlex/pdf2htmlEX"
strip "$BIN"
PKG="$DIST/pkg"
rm -rf "$PKG"
mkdir -p "$PKG/bin" "$PKG/share"
cp "$BIN" "$PKG/bin/"
cp -r "$ROOT/share" "$PKG/share/pdf2htmlEX"
cp "$ROOT"/3rdparty/PDF.js/compatibility.js "$ROOT"/3rdparty/PDF.js/compatibility.min.js "$PKG/share/pdf2htmlEX/"
rm -f "$PKG/share/pdf2htmlEX"/*.in "$PKG/share/pdf2htmlEX"/build_*.sh

TMP=$(mktemp -d)
"$PKG/bin/pdf2htmlEX" "$ROOT/test/data/smoke.pdf" "$TMP/s.html" 2>/dev/null || true
if [ -s "$TMP/s.html" ] && grep -q "Hello pdf2htmlEX revived" "$TMP/s.html"; then
    echo "MACOS STATIC SMOKE TEST PASSED"
else
    echo "SMOKE TEST FAILED" >&2
    exit 1
fi

cd "$DIST" && tar -czf "pdf2htmlEX-macos-${ARCH}.tar.gz" pkg
echo "Done: $DIST/pdf2htmlEX-macos-${ARCH}.tar.gz"
