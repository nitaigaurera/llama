# Takes $1 for Git branch to clone
# Takes $2 for additio CMake flags

set -e

apt update
apt upgrade

apt install git cmake ffmpeg

git clone --branch $1 --depth 1 https://github.com/ggml-org/llama.cpp

cd llama.cpp

C_CXX_ASM="\"                   \
--target=aarch64-linux-android  \
-mcpu=cortex-a78+crypto+crc     \
-ffunction-sections             \
-fdata-sections                 \
-O3 -DNDEBUG\"                  \
"
LD="-Wl,--as-needed,--gc-sections,-s"

MAKE_CMAKE_FLAGS="              \
-DCMAKE_BUILD_TYPE=Release      \
-DBUILD_SHARED_LIBS=ON          \
-DGGML_BACKEND_DL=OFF           \
-DGGML_BUILD_TESTS=OFF          \
-DGGML_BUILD_SERVER=OFF         \
-DGGML_BUILD_EXAMPLES=OFF       \
-DGGML_NATIVE=OFF               \
-DCMAKE_C_FLAGS=$C_CXX_ASM      \
-DCMAKE_CXX_FLAGS=$C_CXX_ASM    \
-DCMAKE_ASM_FLAGS=$C_CXX_ASM    \
-DCMAKE_EXE_LINKER_FLAGS=$LD    \
-DCMAKE_SHARED_LINKER_FLAGS=$LD \
-GGML_LTO=ON                    \
-DGGML_BLAS=OFF                 \
-DGGML_CPU_KLEIDIAI=OFF         \
-DGGML_LLAMAFILE=OFF            \
-DGGML_CPU_ARM_ARCH=\"armv8.2-a+crypto+crc+lse+fp16+rdm+rcpc+dotprod\"                    \
-DGGML_OPENCL=OFF               \
-DGGML_OPENMP=OFF               \
-DGGML_OPENVINO=OFF             \
-DGGML_RPC=OFF                  \
-DGGML_SCHED_MAX_COPIES=1       \
-DGGML_STATIC=OFF               \
-DGGML_SYCL=OFF                 \
-DGGML_VULKAN=OFF               \
-DGGML_VIRTGPU=OFF              \
-DGGML_ZENDNN=OFF               \
-DLLAMA_BUILD_APP=ON            \
-DLLAMA_BUILD_COMMON=ON         \
-DLLAMA_BUILD_EXAMPLES=OFF      \
-DLLAMA_BUILD_IS_DEV=OFF        \
-DLLAMA_BUILD_MTMD=ON           \
-DLLAMA_BUILD_SERVER=ON         \
-DLLAMA_BUILD_TESTS=OFF         \
-DLLAMA_BUILD_TOOLS=ON          \
-DLLAMA_BUILD_UI=ON             \
-DLLAMA_LLGUIDANCE=OFF          \
-DLLAMA_OPENSSL=OFF             \
-DLLAMA_SUBPROCESS=OFF          \
-DLLAMA_UI_GZIP=ON              \
-DLLAMA_USE_PREBUILT_UI=OFF     \
-DMTMD_VIDEO=ON                 \
"

#GGML_STATIC=OFF IS REDUNDANT????
#LLAMA_BUILD_APP=ON MEANS STATICA
# BUILDING IS VIABLE, AND BETTER,
# SINCE ONLY MASTER BINARY WORKS,
# STANDALONE EXAMPLES CAN BE DEL.
#VERY IMPORTANT: WHERE THE MASTER
# FLAGS WERE OFF / TURNED OFF, DA
# SUBFLAGS WAS IGNORED, SO IF YOU
# TURN MASTER FLAGS ON, CHECK THE
# SUBFLAGS, EACH AND EVERYONE
#EXPERIMENT WITH WEBGPU ON OR OFF
#BLAS IS QUESTIONABLE FOR USELESS
#KLEIDIAI IS USEFUL ON Q4_0 /Q8_0
#BLAS VENDOR SHOULD BE OPENBLAS??
#OPENCL, VULKAN, FIND WAYS TO USE
# IF ENABLING OPENCL, SUBFLAGS???
# GGML_OPENCL_EMBED_KERNELS=OFF
# GGML_OPENCL_PROFILING=OFF
# GGML_OPENCL_TARGET_VERSION=?
#  DECIDE ABOVE DYNAMICALLY
# GGML_OPENCL_USE_ADRENO_KERNELS=ON

cmake -B build $MAKE_CMAKE_FLAGS $2
cmake -B build --config Release -j8