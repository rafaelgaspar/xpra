#!/usr/bin/env bash
# Build upstream-style binary debs from the current git tree (rafaelgaspar integration).
# Intended to run inside debian:forky (see .github/workflows/rafaelgaspar-release.yaml).
# NVENC is required: headers + pkg-config + nvcc, then the nvidia deb is checked.
#
# Usage: build-rafaelgaspar-xpra-for-forky.sh <debian-version> [html5-tarball]
set -euo pipefail

DEB_VERSION="${1:?debian version required}"
HTML5_TAR="${2:-}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="${REPO_ROOT}/dist/debian"
# FFmpeg's public NVIDIA Video Codec headers (nvEncodeAPI.h). Not the CUDA toolkit.
NV_CODEC_HEADERS_VERSION="${NV_CODEC_HEADERS_VERSION:-n13.0.19.0}"

mkdir -p "$OUT_DIR"
cd "$REPO_ROOT"

if [[ "$(id -u)" -ne 0 ]]; then
  SUDO=(sudo)
else
  SUDO=()
fi

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
# debuild strips EXTRA_BUILDOPTS; bake --with-nvenc into debian/rules.
sed -i '/^BUILDOPTS :=/s/$/ --with-nvenc/' debian/rules

cat > debian/changelog <<EOF
xpra (${DEB_VERSION}) unstable; urgency=medium

  * rafaelgaspar integration build from git.

 -- Rafael Antunes <me@rafaelgaspar.xyz>  $(date -R)
EOF

export DEB_BUILD_OPTIONS="${DEB_BUILD_OPTIONS:-} noddebs"
export PIP_BREAK_SYSTEM_PACKAGES=1

if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
  "${SUDO[@]}" sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' \
    /etc/apt/sources.list.d/debian.sources || true
fi
"${SUDO[@]}" apt-get update
"${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  pkgconf curl ca-certificates gcc \
  nvidia-cuda-toolkit nvidia-cuda-dev

multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"
hdr_stage="$(mktemp -d)"
curl -fsSL \
  "https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/${NV_CODEC_HEADERS_VERSION}.tar.gz" \
  | tar -xzf - -C "$hdr_stage" --strip-components=1
"${SUDO[@]}" mkdir -p /opt/nvenc/Interface
"${SUDO[@]}" cp -a "${hdr_stage}/include/ffnvcodec/." /opt/nvenc/Interface/
rm -rf "$hdr_stage"
[[ -f /opt/nvenc/Interface/nvEncodeAPI.h ]] || {
  echo "nvEncodeAPI.h missing after nv-codec-headers install" >&2
  exit 1
}

pc_dir="/usr/lib/${multiarch}/pkgconfig"
"${SUDO[@]}" mkdir -p "$pc_dir"
"${SUDO[@]}" tee "${pc_dir}/nvenc.pc" >/dev/null <<EOF
prefix=/opt/nvenc
includedir=\${prefix}/Interface
libdir=/usr/lib/${multiarch}
Name: nvenc
Description: NVENC
Version: 13
Libs: -L\${libdir} -lnvidia-encode
Cflags: -I\${includedir}
EOF

encode_lib="/usr/lib/${multiarch}/libnvidia-encode.so"
if [[ ! -e ${encode_lib}.1 && ! -e $encode_lib ]]; then
  echo 'int NvEncodeAPICreateInstance(void) { return 0; }' \
    | "${SUDO[@]}" gcc -shared -fPIC -Wl,-soname,libnvidia-encode.so.1 \
      -o "${encode_lib}.1" -x c -
  "${SUDO[@]}" ln -sfn libnvidia-encode.so.1 "$encode_lib"
fi
pkg-config --exists nvenc || {
  echo "pkg-config nvenc is missing after install" >&2
  exit 1
}

export CUDA_HOME="${CUDA_HOME:-/usr/lib/cuda}"
if [[ -d ${CUDA_HOME}/bin ]]; then
  export PATH="${CUDA_HOME}/bin:${PATH}"
fi
command -v nvcc >/dev/null || {
  echo "nvcc not found; CUDA kernels (and NVENC) will not build" >&2
  exit 1
}

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
"${SUDO[@]}" ln -sf "$CYTHON_BIN" /usr/local/bin/cython

debuild -b -us -uc
"${REPO_ROOT}/packaging/debian/verify-debs.sh" ../*.deb

shopt -s nullglob
for deb in ../*.deb; do
  base=$(basename "$deb")
  [[ "$base" == xpra-build-deps_* ]] && continue
  cp -a "$deb" "$OUT_DIR/"
done

nvidia_debs=("$OUT_DIR"/xpra-codecs-nvidia_*.deb)
[[ -f ${nvidia_debs[0]} ]] || {
  echo "xpra-codecs-nvidia deb was not built" >&2
  exit 1
}
nvidia_list="$(dpkg-deb -c "${nvidia_debs[0]}")"
echo "$nvidia_list" | grep -q 'xpra/codecs/nvidia/nvenc/encoder' || {
  echo "xpra-codecs-nvidia is missing the NVENC encoder module:" >&2
  echo "$nvidia_list" >&2
  exit 1
}
echo "$nvidia_list" | grep -q 'usr/share/xpra/cuda/.*\.fatbin' || {
  echo "xpra-codecs-nvidia is missing CUDA kernels (.fatbin):" >&2
  echo "$nvidia_list" >&2
  exit 1
}

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
echo "built ${count} debs -> $OUT_DIR"
