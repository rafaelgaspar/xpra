#!/usr/bin/env bash
# Add integration .debs to a reprepro apt tree (dists/ + pool/) for static hosting (GitHub Pages).
#
# Usage: publish-apt-repo.sh <apt-repo-dir> <debs-dir>
set -euo pipefail

REPO_DIR="${1:?apt repository base directory}"
DEB_DIR="${2:?directory containing .deb files}"
SUITE="${RAFAELGASPAR_DEBIAN_SUITE:-forky}"

[[ -d "$DEB_DIR" ]] || { echo "missing debs dir: $DEB_DIR" >&2; exit 1; }
mkdir -p "$REPO_DIR/conf"

SIGN_WITH="!"
if [[ -n "${APT_SIGN_KEY_ID:-}" && -n "${APT_REPO_GPG_PRIVATE_KEY:-}" ]]; then
  SIGN_WITH="${APT_SIGN_KEY_ID}"
fi

cat >"$REPO_DIR/conf/distributions" <<EOF
Origin: rafaelgaspar
Label: rafaelgaspar xpra integration
Suite: ${SUITE}
Codename: ${SUITE}
Architectures: amd64
Components: main
Description: rafaelgaspar/xpra integration releases for Debian ${SUITE}
SignWith: ${SIGN_WITH}
EOF

cat >"$REPO_DIR/conf/options" <<EOF
verbose
basedir ${REPO_DIR}
EOF

shopt -s nullglob
count=0
for deb in "$DEB_DIR"/*.deb; do
  base=$(basename "$deb")
  [[ "$base" == xpra-build-deps_* ]] && continue
  reprepro -b "$REPO_DIR" includedeb "$SUITE" "$deb"
  count=$((count + 1))
done

[[ "$count" -gt 0 ]] || { echo "no debs published under $DEB_DIR" >&2; exit 1; }

if [[ -n "${APT_SIGN_KEY_ID:-}" && -n "${APT_REPO_GPG_PUBLIC_ARMOR:-}" ]]; then
  printf '%s\n' "$APT_REPO_GPG_PUBLIC_ARMOR" >"${REPO_DIR}/rafaelgaspar-xpra.gpg.asc"
fi

echo "published ${count} package(s) to ${REPO_DIR} (${SUITE})"
