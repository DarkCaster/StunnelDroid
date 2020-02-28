#!/bin/bash
#

set -e

#script base directory
script_dir="$(cd "$(dirname "$0")" && pwd)"
. "$script_dir/prepare-env.sh.in"
tools_dir="$ANDROID_HOME"

rm -rf "$tools_dir"
mkdir -p "$tools_dir"

"$script_dir/download.sh"

jdk_checksum="jdk.checksum"
jdk_filename=$(awk '{print $2}' "$script_dir/$jdk_checksum")

tools_checksum="tools.checksum"
tools_filename=$(awk '{print $2}' "$script_dir/$tools_checksum")

pushd 1>/dev/null "$tools_dir"

gunzip -c "$script_dir/$jdk_filename" | tar xf -
mv jdk* jdk

7z x "$script_dir/$tools_filename"
yes | sdkmanager --licenses
sdkmanager --install ndk-bundle

popd 1>/dev/null