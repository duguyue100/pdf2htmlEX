pdf2htmlEX 0.19.0 — revived

This is the first release of the revived pdf2htmlEX. The source tree was
synced with the maintained fork (pdf2htmlEX/pdf2htmlEX v0.18.8.rc1) and
ported forward to modern dependencies:

- poppler >= 24.01 (statically linked; internal headers exported)
- fontforge 20230101 (statically linked)
- cairo / freetype / glib / fontconfig etc. as required

Every binary below is fully self-contained:

- linux x86_64 / aarch64: musl static build (`file` reports
  "statically linked"); no runtime libraries needed on any distro
- macOS arm64 (Apple Silicon): all third-party deps linked statically;
  only system frameworks (libSystem, libiconv, CoreFoundation/Foundation)
  remain dynamic

Usage: unpack, then run `bin/pdf2htmlEX`. The binary locates its resources
in `share/pdf2htmlEX/` relative to its own path, so keep the `pkg/`
layout together (rename the directory freely).

Notes and limitations:

- JPEG2000 images are not decoded in static builds (openjpeg disabled);
  such images render as gaps.
- Output text is always English UI strings in static builds (NLS stubbed).
- The linux binaries are built on Alpine (musl); DNS resolution behavior
  may differ from glibc systems.

Source changes over v0.18.8.rc1 are summarized in the git history of this
repository.
