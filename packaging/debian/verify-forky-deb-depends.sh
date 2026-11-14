#!/usr/bin/env bash
# Fail if the built debs cannot be installed together on this Debian suite.
# Canonical copy lives next to build-rafaelgaspar-xpra-for-forky.sh.
#
# Skips packages whose Depends are known-absent on Debian (AMD proprietary,
# GNOME Shell extensions). Everything else, including xpra-codecs-nvidia, must
# be co-installable from the suite plus these debs.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <deb>..." >&2
  exit 1
fi

skip_pkg() {
  case "$1" in
    xpra-codecs-amd | xpra-client-gnome | xpra-build-deps)
      return 0
      ;;
  esac
  return 1
}

debs=()
for deb in "$@"; do
  [[ -f "$deb" ]] || continue
  pkg=$(dpkg-deb -f "$deb" Package)
  if skip_pkg "$pkg"; then
    echo "skip Debian-install check for $pkg ($(dpkg-deb -f "$deb" Depends))"
    continue
  fi
  debs+=("$deb")
done

[[ ${#debs[@]} -gt 0 ]] || {
  echo "no debs to dependency-check" >&2
  exit 1
}

echo "checking ${#debs[@]} deb(s) are co-installable on $(lsb_release -cs 2>/dev/null || echo unknown)"
if ! DEBIAN_FRONTEND=noninteractive apt-get install --dry-run -y --no-install-recommends \
  "${debs[@]}"; then
  echo "built debs are not co-installable; Depends vs apt-cache:" >&2
  for deb in "${debs[@]}"; do
    pkg=$(dpkg-deb -f "$deb" Package)
    echo "--- $pkg ---" >&2
    dpkg-deb -f "$deb" Depends >&2 || true
    dpkg-deb -f "$deb" Depends \
      | tr ',' '\n' \
      | sed 's/^[[:space:]]*//' \
      | awk '{print $1}' \
      | while read -r dep; do
          [[ -n $dep && $dep != xpra* ]] || continue
          apt-cache policy "$dep" 2>/dev/null | sed -n '1,3p' >&2 || true
        done
  done
  exit 1
fi
echo "built debs are co-installable"
