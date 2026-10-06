#!/data/data/com.termux/files/usr/bin/bash
# ============================================================================
# llama.cpp build script — Termux, OnePlus Nord CE3 (Snapdragon 782G)
# Target: Android 15 / API level 35
# CPU:    4x Cortex-A78 + 4x Cortex-A55 (Kryo 670)
#         Features confirmed via /proc/cpuinfo: dotprod, fp16, lse, rdm,
#         rcpc, crypto (aes/pmull/sha1/sha2), crc32
#         Not present: sve, sme, i8mm (matmul_int8) — genuine hardware gaps
# GPU:    Adreno 610 — not targeted (no GPU backend enabled)
# ============================================================================
set -e  # exit immediately if any command fails

echo "== Step 1: System packages =="
pkg update && pkg upgrade -y
pkg install git cmake clang openssl ffmpeg -y

echo "== Step 2: Clone source =="
if [ ! -d "llama.cpp" ]; then
  git clone https://github.com/ggml-org/llama.cpp
fi
cd llama.cpp

echo "== Step 3: Configure =="
# NOTE on --target=aarch64-linux-android35:
#   Required (not just -D__ANDROID_API__=35) because Bionic gates newer
#   symbols (e.g. posix_spawn_file_actions_addchdir_np, needed by
#   LLAMA_SUBPROCESS/MTMD_VIDEO for ffmpeg spawning) behind Clang's
#   __INTRODUCED_IN availability attribute, which is only set from the
#   compiler's parsed target triple — a plain -D macro never reaches it.
#
# NOTE on armv8.2-a (not armv8.4-a):
#   Cortex-A78 is an Armv8.2-A core with specific optional extensions,
#   not a full Armv8.4-A implementation. Setting -march=armv8.4-a tells
#   the compiler every 8.4A *mandatory baseline* instruction is safe to
#   emit (not just the +features listed), which caused an illegal
#   instruction (SIGILL) crash. armv8.2-a as the base, with the exact
#   confirmed extensions appended via +, only enables what's verified
#   present via /proc/cpuinfo.
CPU_FLAGS="--target=aarch64-linux-android35 -march=armv8.2-a+dotprod+fp16+lse+rdm+rcpc+crypto+crc -mtune=cortex-a78 -ffunction-sections -fdata-sections"

cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$CPU_FLAGS" \
  -DCMAKE_CXX_FLAGS="$CPU_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="-s -Wl,--gc-sections" \
  -DCMAKE_SHARED_LINKER_FLAGS="-s -Wl,--gc-sections" \
  -DGGML_NATIVE=OFF \
  -DGGML_STATIC=OFF \
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_LTO=ON \
  -DGGML_OPENMP=OFF \
  -DGGML_LLAMAFILE=OFF \
  -DGGML_BLAS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_COMMON=ON \
  -DLLAMA_CURL=OFF \
  -DLLAMA_HTTPLIB=ON \
  -DLLAMA_OPENSSL=ON \
  -DLLAMA_SUBPROCESS=ON \
  -DMTMD_VIDEO=ON \
  -DLLAMA_BUILD_TESTS=OFF

  # SHOULD ADD NO_KLEIDIAI ABOVE

echo "== Step 4: Build =="
cmake --build build --config Release -j4

echo "== Step 5: Verify =="
# llama-cli is built under LLAMA_BUILD_EXAMPLES (now OFF), so it will not
# exist. LLAMA_BUILD_SERVER is independent, so llama-server is the binary
# to check here.
./build/bin/llama-server --version

echo "== Build complete. Binaries + shared libs are in build/bin/ =="

# ----------------------------------------------------------------------------
# Optional cleanup (run manually after confirming everything works — not run
# automatically by this script). Uncomment the block below, or run by hand:
# ----------------------------------------------------------------------------
# find build -name "*.o" -delete
# find build -name "CMakeFiles" -type d -exec rm -rf {} +
# mkdir -p ~/llama-bin
# cp build/bin/llama-* ~/llama-bin/ 2>/dev/null
# cp build/bin/*.so ~/llama-bin/ 2>/dev/null
# rm -rf build
# pkg clean
