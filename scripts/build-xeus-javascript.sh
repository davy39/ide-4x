#!/usr/bin/env bash
# Rebuild xeus-javascript from source (0.4.2, with the Emscripten 4 fix from
# the upstream 4x branch / PR #42) and install it over the wasm kernels env.
#
# Why: the emscripten-forge-4x conda channel only ships xeus-javascript builds
# whose `xeus` pin is incompatible with this env:
#   - 0.4.0 has no xeus pin but its binary predates the Emscripten 4 embind
#     fix (convert_json.hpp), so the kernel never starts (infinite loading);
#   - 0.4.2 (fixed source) pins `xeus >=5.2.6,<5.3.0a0`, uninstallable next to
#     xeus 6.0.6 (required by xeus-haskell and the other recent kernels).
# So we compile 0.4.2 locally against the env's xeus 6.0.6.
# The intermediate xeus-lite 5.0.0 (headers moved out of xeus 6) is built too,
# into a staging prefix used for build only (its conda package has the same
# stale xeus pin problem).
# Sources:
#   https://github.com/jupyter-xeus/xeus-javascript (tag 0.4.2)
#   https://github.com/jupyter-xeus/xeus-lite (tag 5.0.0)
set -euo pipefail

XEUS_LITE_VERSION="5.0.0"
XEUS_LITE_SHA256="d0f03b73526f398d43b404170459135abcb2489f9b10ee007c90f7af46f66228"
XEUS_LITE_URL="https://github.com/jupyter-xeus/xeus-lite/archive/refs/tags/${XEUS_LITE_VERSION}.tar.gz"

JS_VERSION="0.4.2"
JS_SHA256="c37f1fb43a3cf0e65a2bc0593083b242fdb40d527667b861bfb41866416d8214"
JS_URL="https://github.com/jupyter-xeus/xeus-javascript/archive/refs/tags/${JS_VERSION}.tar.gz"

ROOT="$PWD"
KERNELS_PREFIX="${ROOT}/.pixi/envs/kernels"
WORK_DIR="${ROOT}/build/wasm-deps"
STAGING_PREFIX="${WORK_DIR}/staging"
MARKER="${KERNELS_PREFIX}/share/xeus-javascript-local-build.txt"

if [ -f "${MARKER}" ] && [ "$(cat "${MARKER}")" = "${JS_VERSION}" ]; then
  echo "xeus-javascript ${JS_VERSION} already built in ${KERNELS_PREFIX}, skipping."
  exit 0
fi

if [ ! -d "${KERNELS_PREFIX}" ]; then
  echo "ERROR: kernels prefix not found at ${KERNELS_PREFIX}. Run setup_kernel first." >&2
  exit 1
fi

command -v emcmake >/dev/null 2>&1 || { echo "ERROR: emcmake not on PATH (missing emscripten package?)" >&2; exit 1; }

mkdir -p "${WORK_DIR}"

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

# xeus-javascript 0.4.2 implements the xeus 5 interpreter interface;
# this env ships xeus 6 (shutdown/interrupt replies). Port it.
apply_js_xeus6_patch() {
  local src_dir="${WORK_DIR}/xeus-javascript-${JS_VERSION}"
  if [ -f "${src_dir}/.xeus6-patched" ]; then
    return 0
  fi
  patch -p1 -d "${src_dir}" < "${ROOT}/scripts/xeus-javascript-xeus6.patch"
  touch "${src_dir}/.xeus6-patched"
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

fetch_and_unpack "xeus-javascript" "${JS_VERSION}" "${JS_SHA256}" "${JS_URL}"
apply_js_xeus6_patch
# xeus-javascript does not set TARGET_SUPPORTS_SHARED_LIBS itself (unlike
# xeus-lite), but it imports the shared `xeus` target, so enable it up front.
cat > "${WORK_DIR}/EmscriptenSharedLibs.cmake" <<'EOF'
set_property(GLOBAL PROPERTY TARGET_SUPPORTS_SHARED_LIBS TRUE)
EOF
emcmake cmake -S "${WORK_DIR}/xeus-javascript-${JS_VERSION}" \
  -B "${WORK_DIR}/xeus-javascript-${JS_VERSION}/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  ${FIND_ROOT_MODES} \
  -DCMAKE_PROJECT_INCLUDE="${WORK_DIR}/EmscriptenSharedLibs.cmake" \
  -DCMAKE_PREFIX_PATH="${STAGING_PREFIX};${KERNELS_PREFIX}" \
  -DCMAKE_INSTALL_PREFIX="${KERNELS_PREFIX}"
cmake --build "${WORK_DIR}/xeus-javascript-${JS_VERSION}/build"
cmake --install "${WORK_DIR}/xeus-javascript-${JS_VERSION}/build"

echo "${JS_VERSION}" > "${MARKER}"
echo "xeus-javascript ${JS_VERSION} installed into ${KERNELS_PREFIX}"
