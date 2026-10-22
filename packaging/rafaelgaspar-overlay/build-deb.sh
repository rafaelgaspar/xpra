#!/usr/bin/env bash
# Build xpra-rafaelgaspar-overlay: diverted overrides on top of xpra.org packages.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <deb-version> <xpra-upstream-version> [html5-tarball] [html5-upstream-version]" >&2
  exit 1
fi

DEB_VERSION="$1"
UPSTREAM_VERSION="${2#v}"
HTML5_TARBALL="${3:-}"
HTML5_UPSTREAM="${4:-}"
HTML5_UPSTREAM="${HTML5_UPSTREAM#v}"
PKG_NAME=xpra-rafaelgaspar-overlay
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OVERLAY_DIR="$(cd "$(dirname "$0")" && pwd)"
STAGING="$(mktemp -d)"
PKG_ROOT="${STAGING}/${PKG_NAME}_${DEB_VERSION}_all"
DEBIAN="${PKG_ROOT}/DEBIAN"

install -d -m 0755 "${DEBIAN}"
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

bundle_html5=0
if [[ -n "${HTML5_TARBALL}" ]]; then
  bundle_html5=1
  install -d -m 0755 "${PKG_ROOT}/usr/share/xpra/www"
  html5_staging="$(mktemp -d)"
  tar -xzf "${HTML5_TARBALL}" -C "${html5_staging}"
  html5_root="$(find "${html5_staging}" -mindepth 1 -maxdepth 1 -type d | head -1)"
  cp -a "${html5_root}/html5/." "${PKG_ROOT}/usr/share/xpra/www/"
  rm -rf "${html5_staging}"
fi

replaces="xpra-x11, xpra-common"
breaks="xpra-server (<< ${UPSTREAM_VERSION}), xpra-x11 (<< ${UPSTREAM_VERSION}), xpra-common (<< ${UPSTREAM_VERSION})"
if [[ "${bundle_html5}" -eq 1 ]]; then
  replaces="${replaces}, xpra-html5"
  if [[ -n "${HTML5_UPSTREAM}" ]]; then
    breaks="${breaks}, xpra-html5 (<< ${HTML5_UPSTREAM})"
  fi
fi

{
  echo "Package: ${PKG_NAME}"
  echo "Version: ${DEB_VERSION}"
  echo "Architecture: all"
  echo "Depends: xpra-server (>= ${UPSTREAM_VERSION}), xpra-x11 (>= ${UPSTREAM_VERSION}), xpra-common (>= ${UPSTREAM_VERSION})"
  echo "Replaces: ${replaces}"
  echo "Breaks: ${breaks}"
  echo "Maintainer: Rafael Antunes <me@rafaelgaspar.xyz>"
  echo "Description: rafaelgaspar overlay patches for Xpra"
  echo " Replaces selected modules from xpra-x11, xpra-common and optionally the HTML5"
  echo " client tree. Uses dpkg-divert so xpra.org package upgrades do not overwrite"
  echo " the forked files until this package is rebuilt for a new upstream version."
} > "${DEBIAN}/control"

install -m 0755 "${OVERLAY_DIR}/preinst" "${DEBIAN}/preinst"
install -m 0755 "${OVERLAY_DIR}/prerm" "${DEBIAN}/prerm"

OUT_DIR="${REPO_ROOT}/dist"
mkdir -p "${OUT_DIR}"
dpkg-deb --build --root-owner-group "${PKG_ROOT}" "${OUT_DIR}/${PKG_NAME}_${DEB_VERSION}_all.deb"
rm -rf "${STAGING}"

echo "built ${OUT_DIR}/${PKG_NAME}_${DEB_VERSION}_all.deb"
