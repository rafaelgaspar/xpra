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

CODENAME="$(lsb_release -cs 2>/dev/null || echo trixie)"
perl -i.bak -pe "s/#${CODENAME}:/#${CODENAME}:\\n/g" debian/control

cat > debian/changelog <<EOF
xpra (${DEB_VERSION}) unstable; urgency=medium

  * rafaelgaspar integration build from git.

 -- Rafael Antunes <me@rafaelgaspar.xyz>  $(date -R)
EOF

export DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:-} noddebs"
export PIP_BREAK_SYSTEM_PACKAGES=1

mk-build-deps --install --tool='apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends --yes' debian/control
rm -f xpra-build-deps* 2>/dev/null || true
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3-pip
pip3 install --upgrade 'cython>=3'

debuild -b -us -uc
"${REPO_ROOT}/packaging/debian/verify-debs.sh" ../*.deb

shopt -s nullglob
for deb in ../*.deb; do
  cp -a "$deb" "$OUT_DIR/"
done

MANIFEST="$OUT_DIR/deb-manifest.txt"
{
  for pattern in \
    xpra-common_*_all.deb \
    xpra-codecs_*_amd64.deb \
    xpra-codecs-extras_*_amd64.deb \
    xpra-codecs-nvidia_*_amd64.deb \
    xpra-x11_*_amd64.deb \
    xpra-audio_*_amd64.deb \
    xpra-audio-server_*_amd64.deb \
    xpra-server_*_amd64.deb \
    xpra-html5_*_all.deb \
    xpra_*_amd64.deb; do
    for f in "$OUT_DIR"/$pattern; do
      [[ -f "$f" ]] && basename "$f"
    done
  done
} >"$MANIFEST"

echo "built $(wc -l <"$MANIFEST") debs -> $OUT_DIR"
