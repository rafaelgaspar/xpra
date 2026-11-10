#!/usr/bin/env bash
# Build upstream-style binary debs from the current git tree (rafaelgaspar integration).
# See fork-pack docs/xpra-full-deb-from-fork.md
#
# Usage: build-rafaelgaspar-from-git.sh <debian-version> [html5-tarball]
set -euo pipefail

DEB_VERSION="${1:?debian version required}"
HTML5_TAR="${2:-}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/dist/debian"

mkdir -p "$OUT_DIR"
cd "$REPO_ROOT"

if [[ -n "$HTML5_TAR" && -f "$HTML5_TAR" ]]; then
  stage="$(mktemp -d)"
  tar -xzf "$HTML5_TAR" -C "$stage"
  root="$(find "$stage" -mindepth 1 -maxdepth 1 -type d | head -1)"
  rm -rf "$REPO_ROOT/html5"
  cp -a "${root}/html5" "$REPO_ROOT/html5"
  rm -rf "$stage"
fi

rm -rf debian
ln -sf packaging/debian/xpra debian

# k3s-home images use debian:forky; integration debs must match that suite
# (not the CI host codename from lsb_release).
CODENAME="${RAFAELGASPAR_DEBIAN_SUITE:-forky}"
perl -i.bak -pe "s/#${CODENAME}:/#${CODENAME}:\\n/g" debian/control

cat > debian/changelog <<EOF
xpra (${DEB_VERSION}) unstable; urgency=medium

  * rafaelgaspar integration build from git.

 -- Rafael Antunes <me@rafaelgaspar.xyz>  $(date -R)
EOF

export DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:-} noddebs"
export PIP_BREAK_SYSTEM_PACKAGES=1

if [[ "$(id -u)" -ne 0 ]]; then
  SUDO=(sudo)
else
  SUDO=()
fi

"${SUDO[@]}" mk-build-deps --install \
  --tool='apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes' \
  debian/control
rm -f xpra-build-deps* 2>/dev/null || true
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-pip
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get remove -y cython3 2>/dev/null || true
python3 -m pip install --upgrade 'cython>=3'
CYTHON_BIN="$(python3 -c 'import shutil; print(shutil.which("cython") or "")')"
if [[ -z "$CYTHON_BIN" || ! -x "$CYTHON_BIN" ]]; then
  echo "cython executable not found after pip install" >&2
  exit 1
fi
"${SUDO[@]}" install -d /usr/local/bin
if [[ "$(readlink -f "$CYTHON_BIN")" != "$(readlink -f /usr/local/bin/cython 2>/dev/null || true)" ]]; then
  "${SUDO[@]}" ln -sf "$CYTHON_BIN" /usr/local/bin/cython
fi

debuild -b -us -uc
"${REPO_ROOT}/packaging/debian/verify-debs.sh" ../*.deb
if [[ "${CODENAME}" == "forky" ]]; then
  chmod +x "${REPO_ROOT}/packaging/debian/verify-forky-package-depends.sh"
  "${REPO_ROOT}/packaging/debian/verify-forky-package-depends.sh" ../*.deb
fi

shopt -s nullglob
for deb in ../*.deb; do
  base=$(basename "$deb")
  [[ "$base" == xpra-build-deps_* ]] && continue
  cp -a "$deb" "$OUT_DIR/"
done

MANIFEST="$OUT_DIR/deb-manifest.txt"
INSTALL_ORDER=(
  xpra-common
  xpra-codecs
  xpra-codecs-extras
  xpra-codecs-nvidia
  xpra-codecs-amd
  xpra-x11
  xpra-audio
  xpra-audio-server
  xpra-server
  xpra-server-wayland
  xpra-wayland
  xpra-html5
  xpra
)
listed=()
emit_deb() {
  local base=$1
  [[ " ${listed[*]} " == *" $base "* ]] && return 0
  listed+=("$base")
  printf '%s\n' "$base"
}
{
  for pkg in "${INSTALL_ORDER[@]}"; do
    for f in "$OUT_DIR"/${pkg}_*.deb; do
      [[ -f "$f" ]] && emit_deb "$(basename "$f")"
    done
  done
  for f in "$OUT_DIR"/xpra-*.deb "$OUT_DIR"/xpra_*.deb; do
    [[ -f "$f" ]] || continue
    emit_deb "$(basename "$f")"
  done
} >"$MANIFEST"

count=$(wc -l <"$MANIFEST")
[[ "$count" -gt 0 ]] || { echo "no debs matched for manifest" >&2; exit 1; }
# deb-manifest must match GitHub release asset names (dpkg ~ → archive .).
sed -i 's/~/./g' "$MANIFEST"
echo "built ${count} debs -> $OUT_DIR"
