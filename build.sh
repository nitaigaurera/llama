#!/usr/bin/env bash

# This entire project is built around the
# following structure.
# Termux is the environment.
# On a OnePlus Nord CE3 8GB.
# llama/ folder is in $WORK.
# With the following within.
# build-static.sh,
# build-shared.sh,
# models/,
# bin/.
# The scripts do as is meant, models/ has
# GGUF models and bin/ the binaries.
# llama.cpp subfolder is also there while
# cloning the sources within this script,
# to be removed only.

#TODO: Copy CMAKE_C_FLAGS to CMAKE_ASM_FLAGS
#TODO: Add BUILD_MTMD and MTMD_VIDEO support
#TODO: --target=aarch64-linux-android35 need
#for some features, can't remember which !!!
#TODO: Test the following benchs with / out,
#BLAS, KleidiAI, OpenCL, Vulkan, WebGPU etc.
#NOTE: `ffmpeg` is required for video modes.
#REMEMBERED: _T=$(git ls-remote --refs --tags --sort=-v:refname $REPO | grep -oPm1 '/\Kv\d+(\.\d+){2}$')
#REMEMBERED: #trap _e ERR; _p() { echo -e "\e[32m> $*\e[m" >&3; }; _e() { echo -e "\e[31m!ERR\e[m" >&3; }
#REMEMBERED: _s() { echo -e "\e[36m> $1\e[m" >&3; }
#REMEMBERED: "Provisioning toolchain"
#            "Finding latest version"
#            "Cloning latest version"
#            "Configuring Buildfiles"
#            "Building llama targets"
#            "SUCCESS!"

# Gemini recommends:
# trap '_e $LINENO "$BASH_COMMAND"' ERR
# _p() { echo -e "\e[32m> $*\e[m" >&3; }
# _e() { echo -e "\e[31m!ERR at line $1: $2\e[m" >&3; }
# and
# export DEBIAN_FRONTEND=noninteractive
# export DPKG_OPTS='-o Dpkg::Options::="--force-confnew" -o Dpkg::Options::="--force-confdef"'
# apt-get install -y $DPKG_OPTS \
#            git \
#          cmake \
#          ninja \
#            npm
# End Gemini

#trap '
#  cd ~/llama
#  rm -rf ~/llama/llama.cpp
#  apt purge --autoremove -y git          \
#                          cmake          \
#                          ninja          \
#                            npm
#' EXIT #cleanup function prototype

exec 3>&2 >.out 2>.err

set -E -ex -o pipefail

trap '
_e "$BASH_COMMAND [${PIPESTATUS[@]}]"
' ERR

_e() { echo -e "\e[31m$1\e[m" >&3; }

test . -ef $WORK/llama

apt install -y git                        \
             cmake                        \
             ninja                        \
               npm

REPO=https://github.com/ggml-org/llama.cpp

_T=$(
   git ls-remote --refs --tags $REPO    | \
  grep -oP '/\Kv\d+(\.\d+){2}$'         | \
  sort -V                               | \
  tail -1
)

git clone -b $_T --depth 1 $REPO

cd llama.cpp # cd at this point or after ?

C_CPP=(
  -mcpu=cortex-a78 -ffunction-sections    \
                   -fdata-sections        \
                   -flto
)

L=( 
  -Wl,-O2,--gc-sections,-s
)

__=(
  -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_C_FLAGS="${C_CPP[*]}"
  -DCMAKE_CXX_FLAGS="${C_CPP[*]}"
  -DCMAKE_EXE_LINKER_FLAGS="${L[*]}"
# -DBUILD_SHARED_LIBS=OFF here ???
# if removing -DGGML_STATIC=ON, y.
  -DGGML_NATIVE=OFF
# -DGGML_STATIC=ON
  -DLLAMA_BUILD_APP=ON
  -DLLAMA_BUILD_COMMON=ON
  -DLLAMA_BUILD_SERVER=ON
  -DLLAMA_BUILD_TOOLS=ON
  -DLLAMA_BUILD_UI=ON
  -DLLAMA_BUILD_TESTS=OFF
  -DLLAMA_BUILD_EXAMPLES=OFF
  -DLLAMA_USE_PREBUILT_UI=OFF
  -DLLAMA_BUILD_IS_DEV=OFF
  -DGGML_LLAMAFILE=OFF
  -DGGML_OPENMP=OFF
)

cmake -B build -G Ninja "${__[@]}"

cmake --build build

cd ..
rm -rf bin
mv -f llama.cpp/build/bin bin
apt purge --autoremove -y git             \
                        cmake             \
                        ninja             \
                          npm
rm -rf llama.cpp # WELL: SHALL WE KEEP IT ?
