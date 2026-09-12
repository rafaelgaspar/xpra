#!/usr/bin/env bash
# Build xpra-rafaelgaspar: Python overlays on top of xpra.org xpra-server.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <deb-version> [html5-tarball]" >&2
  exit 1
fi

DEB_VERSION="$1"
HTML5_TARBALL="${2:-}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAGING="$(mktemp -d)"
PKG_ROOT="${STAGING}/xpra-rafaelgaspar_${DEB_VERSION}_all"

install -d -m 0755 "${PKG_ROOT}/DEBIAN"
install -d -m 0755 \
  "${PKG_ROOT}/usr/lib/python3/dist-packages/xpra/x11" \
  "${PKG_ROOT}/usr/lib/python3/dist-packages/xpra/x11/shadow" \
  "${PKG_ROOT}/usr/lib/python3/dist-packages/xpra/x11/server" \
  "${PKG_ROOT}/usr/lib/python3/dist-packages/xpra/platform/posix"

install -m 0644 "${REPO_ROOT}/xpra/x11/wm.py" \
  "${PKG_ROOT}/usr/lib/python3/dist-packages/xpra/x11/wm.py"
install -m 0644 "${REPO_ROOT}/xpra/x11/shadow/backends.py" \
  "${PKG_ROOT}/usr/lib/python3/dist-packages/xpra/x11/shadow/backends.py"
install -m 0644 "${REPO_ROOT}/xpra/platform/posix/shadow_server.py" \
  "${PKG_ROOT}/usr/lib/python3/dist-packages/xpra/platform/posix/shadow_server.py"
install -m 0644 "${REPO_ROOT}/xpra/x11/server/xtest_pointer.py" \
  "${PKG_ROOT}/usr/lib/python3/dist-packages/xpra/x11/server/xtest_pointer.py"

depends="xpra-server"
if [[ -n "${HTML5_TARBALL}" ]]; then
  install -d -m 0755 "${PKG_ROOT}/usr/share/xpra/www"
  html5_staging="$(mktemp -d)"
  tar -xzf "${HTML5_TARBALL}" -C "${html5_staging}"
  html5_root="$(find "${html5_staging}" -mindepth 1 -maxdepth 1 -type d | head -1)"
  cp -a "${html5_root}/html5/." "${PKG_ROOT}/usr/share/xpra/www/"
  rm -rf "${html5_staging}"
  depends="${depends}, xpra-html5"
fi

cat > "${PKG_ROOT}/DEBIAN/control" <<EOF
Package: xpra-rafaelgaspar
Version: ${DEB_VERSION}
Architecture: all
Depends: ${depends}
Maintainer: Rafael Antunes <me@rafaelgaspar.xyz>
Description: rafaelgaspar overlay patches for Xpra server
 Replaces selected pure-Python modules from xpra-server after install from xpra.org.
EOF

OUT_DIR="${REPO_ROOT}/dist"
mkdir -p "${OUT_DIR}"
dpkg-deb --build --root-owner-group "${PKG_ROOT}" "${OUT_DIR}/xpra-rafaelgaspar_${DEB_VERSION}_all.deb"
rm -rf "${STAGING}"

echo "built ${OUT_DIR}/xpra-rafaelgaspar_${DEB_VERSION}_all.deb"
