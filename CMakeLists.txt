cmake_minimum_required(VERSION 3.5)
project(pdf2htmlEX CXX C)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build configuration (Debug, Release, RelWithDebInfo, MinSizeRel)")
endif()

option(ENABLE_SVG "Enable SVG support, for generating SVG background images and converting Type 3 fonts" ON)

include_directories(${CMAKE_SOURCE_DIR}/src)

if(NOT DEFINED PDF2HTMLEX_VERSION)
    set(PDF2HTMLEX_VERSION "0.19.0")
endif()
set(ARCHIVE_NAME pdf2htmlex-${PDF2HTMLEX_VERSION})
add_custom_target(dist
    COMMAND git archive --prefix=${ARCHIVE_NAME}/ HEAD
        | bzip2 > ${CMAKE_BINARY_DIR}/${ARCHIVE_NAME}.tar.bz2
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR})

find_package(PkgConfig REQUIRED)

# pdf2htmlEX reaches deep into poppler internals (CairoOutputDev, Matrix, ...)
# which modern poppler does not export from its shared library. We therefore
# require a *statically* built poppler and fontforge whose artifacts are
# installed into a normal prefix; point these at the .a files:
set(POPPLER_STATIC "" CACHE FILEPATH "Path to a statically-built libpoppler.a")
set(FONTFORGE_STATIC "" CACHE FILEPATH "Path to a statically-built libfontforge.a")
# modern poppler no longer compiles CairoOutputDev into libpoppler;
# we compile it ourselves out of the poppler source tree (like pdftocairo does)
set(POPPLER_SOURCE_DIR "" CACHE PATH "poppler source tree")

if(NOT POPPLER_STATIC OR NOT FONTFORGE_STATIC)
    message(FATAL_ERROR "POPPLER_STATIC and FONTFORGE_STATIC are required. "
        "Build poppler (>=24.01) and fontforge (20230101) with "
        "-DBUILD_SHARED_LIBS=OFF (poppler also: -DENABLE_UNSTABLE_API_ABI_HEADERS=ON) "
        "and pass the resulting .a paths.")
endif()

pkg_check_modules(POPPLER_PC REQUIRED poppler>=24.1.0)
include_directories(${POPPLER_PC_INCLUDE_DIRS})
link_directories(${POPPLER_PC_LIBRARY_DIRS})

if(ENABLE_SVG)
    pkg_check_modules(CAIRO REQUIRED cairo>=1.10.0)
    message(STATUS "Trying to locate cairo-svg...")
    find_path(CAIRO_SVG_INCLUDE_PATH cairo-svg.h PATHS ${CAIRO_INCLUDE_DIRS} NO_DEFAULT_PATH)
    if(NOT CAIRO_SVG_INCLUDE_PATH)
        find_path(CAIRO_SVG_INCLUDE_PATH cairo-svg.h PATHS ${CAIRO_INCLUDE_DIRS}/.. NO_DEFAULT_PATH)
    endif()
    if(CAIRO_SVG_INCLUDE_PATH)
        message(STATUS "Found cairo-svg")
        include_directories(${CAIRO_INCLUDE_DIRS} ${CAIRO_SVG_INCLUDE_PATH})
        link_directories(${CAIRO_LIBRARY_DIRS})
        set(ENABLE_SVG 1)
    else()
        message(FATAL_ERROR "Error: no SVG support found in Cairo")
    endif()

    find_package(Freetype REQUIRED)
    include_directories(${FREETYPE_INCLUDE_DIRS})
    link_directories(${FREETYPE_LIBRARY_DIRS})
endif()

# fontforge >= 20230101 installs neither a pkg-config file nor headers;
# headers must be exported manually into <prefix>/include/fontforge
pkg_check_modules(GLIB2 REQUIRED glib-2.0)
include_directories(${GLIB2_INCLUDE_DIRS})
find_path(FONTFORGE_INCLUDE_DIR fontforge.h PATH_SUFFIXES fontforge)
if(NOT FONTFORGE_INCLUDE_DIR)
    message(FATAL_ERROR "fontforge development headers not found")
endif()
include_directories(${FONTFORGE_INCLUDE_DIR})

# the two static archives plus their transitive dependencies
set(PDF2HTMLEX_LIBS
    ${FONTFORGE_STATIC}
    ${POPPLER_STATIC}
    ${CAIRO_LIBRARIES}
    ${FREETYPE_LIBRARIES}
    ${GLIB2_LIBRARIES}
)
set(PDF2HTMLEX_TRANSITIVE_DEPS
    "fontconfig;libjpeg;libpng16;libopenjp2;lcms2;libtiff-4;gobject-2.0;gio-2.0;libxml-2.0;libspiro"
    CACHE STRING "pkg-config modules needed by the two static archives")
foreach(_mod ${PDF2HTMLEX_TRANSITIVE_DEPS})
    pkg_check_modules(PC_${_mod} QUIET ${_mod})
    if(PC_${_mod}_FOUND)
        list(APPEND PDF2HTMLEX_LIBS ${PC_${_mod}_LIBRARIES})
        include_directories(${PC_${_mod}_INCLUDE_DIRS})
    endif()
endforeach()
# giflib has no pkg-config file; clear this where it is not available
set(PDF2HTMLEX_GIF_LIBRARY "-lgif" CACHE STRING
    "Link flags for giflib (empty if unavailable)")
list(APPEND PDF2HTMLEX_LIBS ${PDF2HTMLEX_GIF_LIBRARY} -lz -lm -lpthread)

# fully-static builds may need extra low-level archives appended after
# everything else so ld can resolve transitive references
set(PDF2HTMLEX_EXTRA_STATIC_LIBS "" CACHE STRING
    "Extra libraries appended at the end of the link line")
list(APPEND PDF2HTMLEX_LIBS ${PDF2HTMLEX_EXTRA_STATIC_LIBS})

# optional NLS-less libintl implementation compiled directly into the binary
set(PDF2HTMLEX_INTL_STUB "" CACHE FILEPATH
    "libintl stub .c file to compile into pdf2htmlEX")

if(NOT EXISTS ${POPPLER_SOURCE_DIR}/poppler/CairoOutputDev.cc)
    message(FATAL_ERROR "POPPLER_SOURCE_DIR must point at a poppler >=24.01 source tree "
        "(CairoOutputDev.cc is no longer part of the library)")
endif()
include_directories(${POPPLER_SOURCE_DIR} ${POPPLER_SOURCE_DIR}/build)

# generic flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

configure_file (${CMAKE_SOURCE_DIR}/src/pdf2htmlEX-config.h.in ${CMAKE_SOURCE_DIR}/src/pdf2htmlEX-config.h)
configure_file (${CMAKE_SOURCE_DIR}/pdf2htmlEX.1.in ${CMAKE_SOURCE_DIR}/pdf2htmlEX.1)

include(${CMAKE_SOURCE_DIR}/src/css_class_names.cmakelists.txt)
configure_file (${CMAKE_SOURCE_DIR}/src/util/css_const.h.in ${CMAKE_SOURCE_DIR}/src/util/css_const.h)
configure_file (${CMAKE_SOURCE_DIR}/share/base.css.in ${CMAKE_SOURCE_DIR}/share/base.css)
configure_file (${CMAKE_SOURCE_DIR}/share/fancy.css.in ${CMAKE_SOURCE_DIR}/share/fancy.css)
configure_file (${CMAKE_SOURCE_DIR}/share/pdf2htmlEX.js.in ${CMAKE_SOURCE_DIR}/share/pdf2htmlEX.js)

set(PDF2HTMLEX_SRC ${PDF2HTMLEX_SRC}
    src/Param.h
    src/pdf2htmlEX.cc
    src/pdf2htmlEX-config.h
    src/HTMLRenderer/HTMLRenderer.h
    src/HTMLRenderer/draw.cc
    src/HTMLRenderer/general.cc
    src/HTMLRenderer/image.cc
    src/HTMLRenderer/font.cc
    src/HTMLRenderer/form.cc
    src/HTMLRenderer/link.cc
    src/HTMLRenderer/outline.cc
    src/HTMLRenderer/state.cc
    src/HTMLRenderer/text.cc
    src/BackgroundRenderer/BackgroundRenderer.h
    src/BackgroundRenderer/BackgroundRenderer.cc
    src/BackgroundRenderer/SplashBackgroundRenderer.h
    src/BackgroundRenderer/SplashBackgroundRenderer.cc
    src/BackgroundRenderer/CairoBackgroundRenderer.h
    src/BackgroundRenderer/CairoBackgroundRenderer.cc
    src/util/const.h
    src/util/const.cc
    src/util/css_const.h
    src/util/encoding.h
    src/util/encoding.cc
    src/util/ffw.h
    src/util/ffw.c
    src/util/math.h
    src/util/math.cc
    src/util/misc.h
    src/util/misc.cc
    src/util/namespace.h
    src/util/path.h
    src/util/path.cc
    src/util/unicode.h
    src/util/unicode.cc
    src/util/mingw.h
    src/util/mingw.cc
    src/util/SignalHandler.h
    src/util/SignalHandler.cc
    src/ArgParser.h
    src/ArgParser.cc
    src/Base64Stream.h
    src/Base64Stream.cc
    src/Color.h
    src/Color.cc
    src/CoveredTextDetector.h
    src/CoveredTextDetector.cc
    src/DrawingTracer.h
    src/DrawingTracer.cc
    src/HTMLState.h
    src/HTMLTextLine.h
    src/HTMLTextLine.cc
    src/HTMLTextPage.h
    src/HTMLTextPage.cc
    src/Preprocessor.h
    src/Preprocessor.cc
    src/StringFormatter.h
    src/StringFormatter.cc
    src/TmpFiles.h
    src/TmpFiles.cc
    )

set(PDF2HTMLEX_SRC ${PDF2HTMLEX_SRC}
    ${POPPLER_SOURCE_DIR}/poppler/CairoFontEngine.h
    ${POPPLER_SOURCE_DIR}/poppler/CairoFontEngine.cc
    ${POPPLER_SOURCE_DIR}/poppler/CairoRescaleBox.h
    ${POPPLER_SOURCE_DIR}/poppler/CairoRescaleBox.cc
    ${POPPLER_SOURCE_DIR}/poppler/CairoOutputDev.h
    ${POPPLER_SOURCE_DIR}/poppler/CairoOutputDev.cc)

add_executable(pdf2htmlEX ${PDF2HTMLEX_SRC})
if(PDF2HTMLEX_INTL_STUB)
    target_sources(pdf2htmlEX PRIVATE ${PDF2HTMLEX_INTL_STUB})
endif()
target_link_libraries(pdf2htmlEX ${PDF2HTMLEX_LIBS})

add_custom_target(pdf2htmlEX_resources ALL DEPENDS
    ${CMAKE_SOURCE_DIR}/share/base.min.css
    ${CMAKE_SOURCE_DIR}/share/fancy.min.css
    ${CMAKE_SOURCE_DIR}/share/pdf2htmlEX.min.js
    )

add_custom_command(OUTPUT ${CMAKE_SOURCE_DIR}/share/pdf2htmlEX.min.js
    COMMAND ${CMAKE_SOURCE_DIR}/share/build_js.sh
    DEPENDS
        ${CMAKE_SOURCE_DIR}/share/build_js.sh
        ${CMAKE_SOURCE_DIR}/share/pdf2htmlEX.js
    )

add_custom_command(OUTPUT
        ${CMAKE_SOURCE_DIR}/share/base.min.css
        ${CMAKE_SOURCE_DIR}/share/fancy.min.css
    COMMAND ${CMAKE_SOURCE_DIR}/share/build_css.sh
    DEPENDS
        ${CMAKE_SOURCE_DIR}/share/build_css.sh
        ${CMAKE_SOURCE_DIR}/share/base.css
        ${CMAKE_SOURCE_DIR}/share/fancy.css
    )

install (TARGETS pdf2htmlEX DESTINATION bin)

set(PDF2HTMLEX_RESOURCE
    ${CMAKE_SOURCE_DIR}/3rdparty/PDF.js/compatibility.js
    ${CMAKE_SOURCE_DIR}/3rdparty/PDF.js/compatibility.min.js
    ${CMAKE_SOURCE_DIR}/share/base.css
    ${CMAKE_SOURCE_DIR}/share/base.min.css
    ${CMAKE_SOURCE_DIR}/share/fancy.css
    ${CMAKE_SOURCE_DIR}/share/fancy.min.css
    ${CMAKE_SOURCE_DIR}/share/LICENSE
    ${CMAKE_SOURCE_DIR}/share/manifest
    ${CMAKE_SOURCE_DIR}/share/pdf2htmlEX.js
    ${CMAKE_SOURCE_DIR}/share/pdf2htmlEX.min.js
    ${CMAKE_SOURCE_DIR}/share/pdf2htmlEX-64x64.png
    )
install (FILES ${PDF2HTMLEX_RESOURCE} DESTINATION share/pdf2htmlEX)
install (FILES pdf2htmlEX.1 DESTINATION share/man/man1)
