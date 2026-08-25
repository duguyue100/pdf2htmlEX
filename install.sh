#!/usr/bin/env bash
set -euo pipefail

REPO="duguyue100/pdf2htmlEX"
PREFIX="${PREFIX:-${HOME}/.local}"
INSTALL_BIN_DIR="${PREFIX}/bin"
INSTALL_SHARE_DIR="${PREFIX}/share/pdf2htmlEX"
TMP_DIR=""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()    { echo "[pdf2htmlEX] $*"; }
success() { echo "[pdf2htmlEX] ✓ $*"; }
warn()    { echo "[pdf2htmlEX] ⚠ $*" >&2; }
die()     { echo "[pdf2htmlEX] ✗ $*" >&2; exit 1; }

check_cmd() { command -v "$1" >/dev/null 2>&1; }

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"

  case "$os" in
    linux)  ;;
    darwin) os="macos" ;;
    *) die "Unsupported OS: $os. Only linux and macOS are supported." ;;
  esac

  case "$arch" in
    x86_64|amd64)  [ "$os" = "linux" ] || die "macOS builds are arm64-only."
                   arch="x86_64" ;;
    aarch64)       arch="aarch64" ;;
    arm64)         arch="arm64" ;;
    *) die "Unsupported architecture: $arch. Only x86_64 and arm64/aarch64 are supported." ;;
  esac

  echo "${os}-${arch}"
}

ensure_dirs() {
  mkdir -p "${INSTALL_BIN_DIR}" "$(dirname "${INSTALL_SHARE_DIR}")"
}

check_path() {
  if echo ":${PATH}:" | grep -q ":${INSTALL_BIN_DIR}:"; then
    return
  fi
  warn "${INSTALL_BIN_DIR} is not in your PATH."
  warn "Add this line to your shell config (~/.bashrc, ~/.zshrc, etc.):"
  warn ""
  warn "  export PATH=\"${INSTALL_BIN_DIR}:\$PATH\""
  warn ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      cat <<EOF
Usage: install.sh [--prefix DIR]

Download the latest pdf2htmlEX release from GitHub and install it to
~/.local (bin + share), or to DIR when --prefix is given.

Environment:
  PREFIX=/usr/local install.sh   # install system-wide instead
EOF
      exit 0
      ;;
    *)
      die "Unknown option: $arg"
      ;;
  esac
done

platform="$(detect_platform)"   # e.g. macos-arm64, linux-x86_64
info "Detected platform: ${platform}"

check_cmd curl || die "'curl' not found."
check_cmd tar  || die "'tar' not found."

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# resolve latest tag via the releases/latest redirect (no API rate limits)
info "Resolving latest release..."
redirect="$(curl -fsSI --connect-timeout 10 --max-time 30 -o /dev/null \
  -w '%{redirect_url}' "https://github.com/${REPO}/releases/latest")" \
  || die "Could not reach github.com (connection failed or timed out)."
tag="${redirect##*/}"
[[ "$tag" == v* ]] || die "Could not determine the latest release tag. Check https://github.com/${REPO}/releases"

asset="pdf2htmlEX-${tag}-${platform}.tar.gz"
download_url="https://github.com/${REPO}/releases/download/${tag}/${asset}"

info "Downloading ${asset}..."
curl -fSL --retry 3 --connect-timeout 10 --max-time 900 --progress-bar "${download_url}" -o "${TMP_DIR}/asset.tar.gz" \
  || die "Download failed (${asset}). See https://github.com/${REPO}/releases for available assets."

tar -xzf "${TMP_DIR}/asset.tar.gz" -C "${TMP_DIR}"
[ -f "${TMP_DIR}/pkg/bin/pdf2htmlEX" ] || die "Unexpected archive layout: pkg/bin/pdf2htmlEX missing."

ensure_dirs
install -m 0755 "${TMP_DIR}/pkg/bin/pdf2htmlEX" "${INSTALL_BIN_DIR}/pdf2htmlEX"
rm -rf "${INSTALL_SHARE_DIR}"
cp -R "${TMP_DIR}/pkg/share/pdf2htmlEX" "${INSTALL_SHARE_DIR}"

# verify the installed binary can find its resources and run
if "${INSTALL_BIN_DIR}/pdf2htmlEX" -v >/dev/null 2>&1; then
  success "Installed pdf2htmlEX ${tag} → ${INSTALL_BIN_DIR}/pdf2htmlEX (resources in ${INSTALL_SHARE_DIR})"
else
  warn "Installed, but 'pdf2htmlEX -v' failed; check resource path ${INSTALL_SHARE_DIR}."
fi
check_path
