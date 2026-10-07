#!/usr/bin/env bash
# Rebuild xeus-javascript from source and install it over the wasm kernels env.
#
# Why: the emscripten-forge-4x conda channel only ships xeus-javascript builds
# whose `xeus` pin is incompatible with this env:
#   - 0.4.0 has no xeus pin but its binary predates the Emscripten 4 embind
#     fix (convert_json.hpp), so the kernel never starts (infinite loading);
#   - 0.4.2 (fixed source) pins `xeus >=5.2.6,<5.3.0a0`, uninstallable next to
#     xeus 6.0.6 (required by xeus-haskell and the other recent kernels).
# So we compile the xeus6 branch of our fork locally against the env's
# xeus 6.0.6. The fork (branch xeus6) ports 0.4.2 to the xeus 6 interpreter
# API and registers the nl::json embind type id for Emscripten 4.
# The intermediate xeus-lite 5.0.0 (headers moved out of xeus 6) is built too,
# into a staging prefix used for build only (its conda package has the same
# stale xeus pin problem).
# Sources (pinned, verified by sha256):
#   https://github.com/davy39/xeus-javascript (branch xeus6, commit JS_COMMIT)
#   https://github.com/jupyter-xeus/xeus-lite (tag 5.0.0)
set -euo pipefail

XEUS_LITE_VERSION="5.0.0"
XEUS_LITE_SHA256="d0f03b73526f398d43b404170459135abcb2489f9b10ee007c90f7af46f66228"
XEUS_LITE_URL="https://github.com/jupyter-xeus/xeus-lite/archive/refs/tags/${XEUS_LITE_VERSION}.tar.gz"

JS_COMMIT="ec88ef797e040f263f0f651797829419bdbe8f52"
JS_SHA256="e9add4e05be0e633dad6066efdb1f4fa738b514608e486f2e57aaf9cd44acb4b"
JS_URL="https://github.com/davy39/xeus-javascript/archive/${JS_COMMIT}.tar.gz"
JS_SRC_DIR="xeus-javascript-${JS_COMMIT}"

ROOT="$PWD"
KERNELS_PREFIX="${ROOT}/.pixi/envs/kernels"
WORK_DIR="${ROOT}/build/wasm-deps"
STAGING_PREFIX="${WORK_DIR}/staging"
MARKER="${KERNELS_PREFIX}/share/xeus-javascript-local-build.txt"
EXPECTED_MARKER="xeus6-${JS_COMMIT}"

if [ -f "${MARKER}" ] && [ "$(cat "${MARKER}")" = "${EXPECTED_MARKER}" ]; then
  echo "xeus-javascript ${EXPECTED_MARKER} already built in ${KERNELS_PREFIX}, skipping."
  exit 0
fi

if [ ! -d "${KERNELS_PREFIX}" ]; then
  echo "ERROR: kernels prefix not found at ${KERNELS_PREFIX}. Run setup_kernel first." >&2
  exit 1
fi

command -v emcmake >/dev/null 2>&1 || { echo "ERROR: emcmake not on PATH (missing emscripten package?)" >&2; exit 1; }

mkdir -p "${WORK_DIR}"
# Legacy unpack dirs from previous script versions.
rm -rf "${ROOT}/build/xeus-javascript" "${WORK_DIR}/xeus-javascript-0.4.2"

fetch_and_unpack() {
  local name="$1" version="$2" sha256="$3" url="$4"
  local tarball="${WORK_DIR}/${name}-${version}.tar.gz"
  local src_dir="${WORK_DIR}/${name}-${version}"
  if [ -d "${src_dir}/include" ] || [ -d "${src_dir}/src" ]; then
    echo "${name} ${version} sources already unpacked."
    return 0
  fi
  python3 - "${url}" "${tarball}" "${sha256}" <<'EOF'
import hashlib, sys, urllib.request
url, dest, expected = sys.argv[1], sys.argv[2], sys.argv[3]
print(f"Downloading {url} ...")
urllib.request.urlretrieve(url, dest)
digest = hashlib.sha256(open(dest, "rb").read()).hexdigest()
if digest != expected:
    print(f"ERROR: sha256 mismatch: got {digest}, expected {expected}", file=sys.stderr)
    sys.exit(1)
print("sha256 OK")
EOF
  rm -rf "${src_dir}"
  tar xzf "${tarball}" -C "${WORK_DIR}"
}

# NOTE: the Emscripten toolchain forces CMAKE_FIND_ROOT_PATH_MODE_*=ONLY,
# which ignores CMAKE_PREFIX_PATH; conda/rattler builds override with BOTH.
FIND_ROOT_MODES="-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH"

# Same flags as the official emscripten-forge recipes.
fetch_and_unpack "xeus-lite" "${XEUS_LITE_VERSION}" "${XEUS_LITE_SHA256}" "${XEUS_LITE_URL}"
emcmake cmake -S "${WORK_DIR}/xeus-lite-${XEUS_LITE_VERSION}" \
  -B "${WORK_DIR}/xeus-lite-${XEUS_LITE_VERSION}/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  ${FIND_ROOT_MODES} \
  -DCMAKE_PREFIX_PATH="${KERNELS_PREFIX}" \
  -DCMAKE_INSTALL_PREFIX="${STAGING_PREFIX}"
cmake --build "${WORK_DIR}/xeus-lite-${XEUS_LITE_VERSION}/build"
cmake --install "${WORK_DIR}/xeus-lite-${XEUS_LITE_VERSION}/build"

fetch_and_unpack "xeus-javascript" "${JS_COMMIT}" "${JS_SHA256}" "${JS_URL}"
emcmake cmake -S "${WORK_DIR}/${JS_SRC_DIR}" \
  -B "${WORK_DIR}/${JS_SRC_DIR}/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  ${FIND_ROOT_MODES} \
  -DCMAKE_PREFIX_PATH="${STAGING_PREFIX};${KERNELS_PREFIX}" \
  -DCMAKE_INSTALL_PREFIX="${KERNELS_PREFIX}"
cmake --build "${WORK_DIR}/${JS_SRC_DIR}/build"
cmake --install "${WORK_DIR}/${JS_SRC_DIR}/build"

echo "${EXPECTED_MARKER}" > "${MARKER}"
echo "xeus-javascript ${EXPECTED_MARKER} installed into ${KERNELS_PREFIX}"
