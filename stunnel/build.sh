#!/bin/bash
#

set -e

api_ver="$1"
arch="$2"
ndk="$3"
ndk_fallback_dir="$4"

[[ -z $api_ver ]] && api_ver="28"
[[ -z $arch ]] && arch="x86"
[[ -z $ndk_fallback_dir ]] && ndk_fallback_dir="$HOME/Android/Sdk/ndk"

host_arch=$(uname -m)

show_usage() {
  [[ ! -z $@ ]] && echo "" && echo "$@"
  echo "usage: build.sh [api version; 28 by default] [arch; x86 by default] [ndk base dir] [ndk fallback directory; ~/Android/Sdk/ndk by default]"
  exit 1
}

#define service directories
script_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$script_dir/build-$arch"
dist="$build_dir/dist"

#validate or find NDK installation directory
if [[ -z $ndk || ! -d $ndk ]]; then
  echo "NDK base directory is not provided or missing"
  echo "Searching for NDK at $ndk_fallback_dir (will use most recent one)"
  ndk=$(find 2>/dev/null "$ndk_fallback_dir" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -n1)
  [[ -z $ndk || ! -d $ndk ]] && show_usage "Failed to auto-detect NDK directory!"
fi
echo "Using NDK at $ndk"

#check platform directory for selected arch and api-version
platform="$ndk/platforms/android-$api_ver/arch-$arch"
[[ ! -d $platform ]] && show_usage "Selected api version or arch is not supported by provided NDK"

echo "Selected platform directory: $platform"

if [[ $arch = "arm" ]]; then
  toolchain_name="armv7a-linux-androideabi"
  strip="arm-linux-androideabi-strip"
elif [[ $arch = "arm64" ]]; then
  toolchain_name="aarch64-linux-android"
elif [[ $arch = "x86" ]]; then
  toolchain_name="i686-linux-android"
elif [[ $arch = "x86_64" ]]; then
  toolchain_name="x86_64-linux-android"
else
  show_usage "Unsupported arch $arch, supported archs: arm, arm64, x86, x86_64"
fi

toolchain="$ndk/toolchains/llvm/prebuilt/linux-$host_arch"
[[ ! -d $toolchain ]] && show_usage "Failed to detect NDK toolchain directory for current host-machine arch!"

echo "Selected toolchain directory: $toolchain"

#setup env
export ANDROID_NDK_HOME="$ndk"
export ANDROID_API="$api_ver"
export PATH="$toolchain/bin:$PATH"
export CC="${toolchain_name}${api_ver}-clang"
export CXX="${toolchain_name}${api_ver}-clang++"
export CFLAGS="-Os -flto"
export CXXFLAGS="-Os -flto"
export LDFLAGS="-O3 -fuse-ld=gold -flto"

#strip utility
strip_fallback="$toolchain_name-strip"
[[ -z $strip ]] && strip="$strip_fallback"

if ! which 1>/dev/null 2>&1 "$strip"; then
  strip="$strip_fallback"
  if ! which 1>/dev/null 2>&1 "$strip"; then
    echo "Strip utility for configured toolchain is not found (this is optional)."
    strip=""
  fi
fi

#download sources if missing and check it's integrity
"$script_dir/download.sh"

#cleanup
rm -rf "$build_dir"
rm -rf "$dist"
mkdir -p "$build_dir"
mkdir -p "$dist"

stunnel_filename=$(awk '{print $2}' "$script_dir/stunnel.checksum")
openssl_filename=$(awk '{print $2}' "$script_dir/openssl.checksum")

pushd 1>/dev/null "$build_dir"

#extract sources
gunzip -c "$script_dir/$openssl_filename" | tar xf -
gunzip -c "$script_dir/$stunnel_filename" | tar xf -

#build openssl
pushd 1>/dev/null openssl-*
./Configure --prefix="$dist" --openssldir=/data/local/tmp/ssl no-tests no-shared android-$arch -D__ANDROID_API__=$api_ver
make
make install_sw
popd 1>/dev/null

#build stunnel
pushd 1>/dev/null stunnel-*
./configure --with-ssl="$dist" --prefix="$dist" --host="$toolchain_name" --with-sysroot="$platform"
make
make install
popd 1>/dev/null

if [[ ! -z $strip ]]; then
  $strip --strip-unneeded "$dist/bin/stunnel"
else
  echo "Skiping strip of final stunnel binary $dist/bin/stunnel"
fi

#TODO: copy target stunnel binary somewhere

popd 1>/dev/null
