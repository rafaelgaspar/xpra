#!/usr/bin/env bash
# Add .debs to a reprepro apt tree (dists/ + pool/) for static hosting (GitHub Pages).
# Canonical copy: rafaelgaspar/fork-pack/scripts/debian/publish-apt-repo.sh
#
# Usage: publish-apt-repo.sh <apt-repo-dir> <debs-dir>
#
# Environment:
#   RAFAELGASPAR_DEBIAN_SUITE   (default: forky)
#   APT_ORIGIN                  (default: rafaelgaspar)
#   APT_LABEL                   (default: rafaelgaspar integration)
#   APT_DESCRIPTION             (optional; defaults from APT_LABEL + suite)
#   APT_ARCHITECTURES           (default: amd64; reprepro forbids "all")
#   APT_COMPONENTS              (default: main)
#   APT_GPG_ASC_FILENAME        (default: rafaelgaspar-apt.gpg.asc)
#   APT_DEB_SKIP_PATTERN        (grep -E; default: xpra-build-deps_)
#   APT_REPO_SIGNING, APT_SIGN_KEY_ID, APT_REPO_GPG_PUBLIC_ARMOR — signing (CI)
set -euo pipefail

REPO_DIR="${1:?apt repository base directory}"
DEB_DIR="${2:?directory containing .deb files}"
SUITE="${RAFAELGASPAR_DEBIAN_SUITE:-forky}"
ORIGIN="${APT_ORIGIN:-rafaelgaspar}"
LABEL="${APT_LABEL:-rafaelgaspar integration}"
# reprepro: "Distribution … contains an architecture called 'all'".
# Architecture: all debs still index under the real arches listed here.
ARCHITECTURES="${APT_ARCHITECTURES:-amd64}"
read -r -a _apt_arches <<< "$ARCHITECTURES"
_apt_filtered=()
for _a in "${_apt_arches[@]}"; do
  [[ $_a == all ]] && continue
  _apt_filtered+=("$_a")
done
((${#_apt_filtered[@]} > 0)) || _apt_filtered=(amd64)
ARCHITECTURES="${_apt_filtered[*]}"
unset _apt_arches _apt_filtered _a
COMPONENTS="${APT_COMPONENTS:-main}"
GPG_ASC="${APT_GPG_ASC_FILENAME:-rafaelgaspar-apt.gpg.asc}"
SKIP_PATTERN="${APT_DEB_SKIP_PATTERN:-xpra-build-deps_}"
DESCRIPTION="${APT_DESCRIPTION:-${LABEL} for Debian ${SUITE}}"

[[ -d "$DEB_DIR" ]] || { echo "missing debs dir: $DEB_DIR" >&2; exit 1; }
mkdir -p "$REPO_DIR/conf"

SIGN_BLOCK=""
if [[ "${APT_REPO_SIGNING:-}" == 1 && -n "${APT_SIGN_KEY_ID:-}" ]]; then
  SIGN_BLOCK=$(printf 'SignWith: %s\n' "${APT_SIGN_KEY_ID}")
fi

cat >"$REPO_DIR/conf/distributions" <<EOF
Origin: ${ORIGIN}
Label: ${LABEL}
Suite: ${SUITE}
Codename: ${SUITE}
Architectures: ${ARCHITECTURES}
Components: ${COMPONENTS}
Description: ${DESCRIPTION}
${SIGN_BLOCK}
EOF

cat >"$REPO_DIR/conf/options" <<EOF
verbose
basedir ${REPO_DIR}
EOF

shopt -s nullglob
count=0
for deb in "$DEB_DIR"/*.deb; do
  base=$(basename "$deb")
  if [[ -n "$SKIP_PATTERN" ]] && echo "$base" | grep -Eq "$SKIP_PATTERN"; then
    continue
  fi
  reprepro -b "$REPO_DIR" includedeb "$SUITE" "$deb"
  count=$((count + 1))
done

[[ "$count" -gt 0 ]] || { echo "no debs published under $DEB_DIR" >&2; exit 1; }

if [[ -n "${APT_SIGN_KEY_ID:-}" && -n "${APT_REPO_GPG_PUBLIC_ARMOR:-}" ]]; then
  printf '%s\n' "$APT_REPO_GPG_PUBLIC_ARMOR" >"${REPO_DIR}/${GPG_ASC}"
fi

echo "published ${count} package(s) to ${REPO_DIR} (${SUITE})"
