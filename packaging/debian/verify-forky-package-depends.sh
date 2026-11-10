#!/bin/bash
# After debuild on forky: catch duplicate libopenjph SONAMEs in Depends (control
# vs dh_shlibdeps). Full apt solvability is left to the integration image build.
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "verify-forky-package-depends: no packages" >&2
  exit 1
fi

FAILED=0

dep_pkg_name() {
  local tok="$1"
  tok="${tok#"${tok%%[![:space:]]*}"}"
  tok="${tok%"${tok##*[![:space:]]}"}"
  tok="${tok%%|*}"
  tok="${tok%%:*}"
  tok="${tok%%(*}"
  tok="${tok%% *}"
  printf '%s' "$tok"
}

openjph_family() {
  case "$1" in libopenjph*) return 0 ;; esac
  return 1
}

for deb in "$@"; do
  [[ -f "$deb" ]] || continue
  case "$(basename "$deb")" in
    xpra-build-deps_*) continue ;;
  esac
  depends=$(dpkg-deb -f "$deb" Depends 2>/dev/null || true)
  [[ -n "$depends" ]] || continue

  declare -A seen_openjph=()
  while IFS= read -r raw; do
    raw="${raw#"${raw%%[![:space:]]*}"}"
    raw="${raw%"${raw##*[![:space:]]}"}"
    [[ -z "$raw" ]] && continue
    pkg=$(dep_pkg_name "$raw")
    [[ -z "$pkg" ]] && continue

    if openjph_family "$pkg"; then
      if [[ -n "${seen_openjph[$pkg]:-}" ]]; then
        continue
      fi
      if ((${#seen_openjph[@]} > 0)); then
        echo "verify-forky-package-depends: $deb: conflicting openjph runtime deps (${!seen_openjph[*]} and $pkg)" >&2
        FAILED=1
      fi
      seen_openjph[$pkg]=1
    fi
  done < <(tr ',' '\n' <<<"$depends")
done

exit "$FAILED"
