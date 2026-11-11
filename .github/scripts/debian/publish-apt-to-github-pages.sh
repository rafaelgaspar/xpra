#!/usr/bin/env bash
# Clone or init gh-pages, run reprepro in debian:forky, commit and push apt tree.
# Canonical copy: rafaelgaspar/fork-pack/scripts/debian/publish-apt-to-github-pages.sh
#
# Usage: publish-apt-to-github-pages.sh <debs-dir>
#
# Required environment:
#   GH_TOKEN, GITHUB_REPOSITORY, APT_PAGES_COMMIT_LABEL (e.g. integration tag)
#
# Optional:
#   FORKY_IMAGE (default: pinned debian:forky)
#   APT_PAGES_SUBDIR (default: apt)
#   APT_PAGES_README (multiline; written when gh-pages is new)
#   RAFAELGASPAR_FORK_PACK (path to fork-pack checkout; default: script dir/..)
#   Plus all publish-apt-repo.sh APT_* / signing variables
set -euo pipefail

DEB_DIR="${1:?directory containing .deb files}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY required}"
GH_TOKEN="${GH_TOKEN:?GH_TOKEN required}"
COMMIT_LABEL="${APT_PAGES_COMMIT_LABEL:?APT_PAGES_COMMIT_LABEL required}"
FORKY_IMAGE="${FORKY_IMAGE:-debian:forky@sha256:49c219ade93d7c11635c0d57e735ed82339a503a4376cd6957046c2bd4e5905b}"
APT_SUBDIR="${APT_PAGES_SUBDIR:-apt}"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pack_root="${RAFAELGASPAR_FORK_PACK:-$(cd "$script_dir/../.." && pwd)}"
publish_apt="${pack_root}/scripts/debian/publish-apt-repo.sh"
[[ -x "$publish_apt" ]] || { echo "missing $publish_apt" >&2; exit 1; }

pages_dir="${RUNNER_TEMP:-/tmp}/apt-pages-$$"
rm -rf "$pages_dir"
if git ls-remote --heads "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" gh-pages | grep -q gh-pages; then
  git clone --depth=1 -b gh-pages \
    "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
    "$pages_dir"
else
  mkdir -p "$pages_dir"
  git -C "$pages_dir" init -b gh-pages
  if [[ -n "${APT_PAGES_README:-}" ]]; then
    printf '%s\n' "$APT_PAGES_README" >"$pages_dir/README.md"
  else
    owner="${GITHUB_REPOSITORY%%/*}"
  repo="${GITHUB_REPOSITORY#*/}"
    printf '%s\n' "# ${repo}" "# Apt: https://${owner}.github.io/${repo}/${APT_SUBDIR}" >"$pages_dir/README.md"
  fi
fi

mkdir -p "${pages_dir}/${APT_SUBDIR}"

key_mount=()
if [[ -n "${APT_REPO_GPG_PRIVATE_KEY:-}" ]]; then
  key_file="${RUNNER_TEMP:-/tmp}/apt-signing.key"
  install -m 600 /dev/null "$key_file" 2>/dev/null || { : >"$key_file"; chmod 600 "$key_file"; }
  printf '%s' "$APT_REPO_GPG_PRIVATE_KEY" >"$key_file"
  key_mount=(-v "${key_file}:/apt-signing.key:ro")
fi

signing_env=()
if [[ -n "${APT_REPO_GPG_PRIVATE_KEY:-}" && -n "${APT_SIGN_KEY_ID:-}" ]]; then
  signing_env=(-e APT_REPO_SIGNING=1)
fi

docker run --rm \
  -e DEBIAN_FRONTEND=noninteractive \
  -e RAFAELGASPAR_DEBIAN_SUITE="${RAFAELGASPAR_DEBIAN_SUITE:-forky}" \
  -e APT_ORIGIN -e APT_LABEL -e APT_DESCRIPTION -e APT_ARCHITECTURES \
  -e APT_COMPONENTS -e APT_GPG_ASC_FILENAME -e APT_DEB_SKIP_PATTERN \
  -e APT_SIGN_KEY_ID -e APT_REPO_GPG_PUBLIC_ARMOR \
  "${signing_env[@]}" \
  -v "${pack_root}:/fork-pack:ro" \
  -v "$(cd "$DEB_DIR" && pwd):/debs:ro" \
  -v "${pages_dir}/${APT_SUBDIR}:/repo" \
  "${key_mount[@]}" \
  "${FORKY_IMAGE}" \
  bash -euxo pipefail -c '
    apt-get update
    apt-get install -y --no-install-recommends reprepro gnupg ca-certificates
    if [[ "${APT_REPO_SIGNING:-}" == 1 && -f /apt-signing.key ]]; then
      export GNUPGHOME=/tmp/gnupg
      install -d -m 700 "$GNUPGHOME"
      gpg --batch --import /apt-signing.key
    fi
    /fork-pack/scripts/debian/publish-apt-repo.sh /repo /debs
  '

git -C "$pages_dir" add -A
git -C "$pages_dir" -c user.name="Rafael Antunes" -c user.email="me@rafaelgaspar.xyz" \
  diff --staged --quiet || \
  git -C "$pages_dir" -c user.name="Rafael Antunes" -c user.email="me@rafaelgaspar.xyz" \
    commit -m "apt: integrate ${COMMIT_LABEL}"
git -C "$pages_dir" push \
  "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
  HEAD:gh-pages

echo "pushed apt tree to gh-pages (${GITHUB_REPOSITORY}/${APT_SUBDIR})"
