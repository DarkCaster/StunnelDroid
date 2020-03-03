#!/bin/bash
#

# build script for CI

operation="$1"
build_id="$2"
event_type="$3"

set -eE

ping_pid=""

run_ping() {
  echo "starting build timer"
  (
    set +eE
    trap - ERR
    timer="0"
    while true; do
      sleep 60
      (( timer += 1 ))
      echo "building: $timer min"
    done
  ) &
  ping_pid="$!"
}

stop_ping() {
  if [[ ! -z $ping_pid ]]; then
    2>/dev/null kill -SIGTERM $ping_pid || true
    2>/dev/null wait $ping_pid || true
    ping_pid=""
  fi
}

show_usage() {
  [[ ! -z "$1" ]] && echo "$1" && echo ""
  echo "usage: build.sh [operation] [build_id] [event type]"
  echo "see invocation examples at .travis.yml"
  exit 2
}

script_dir="$( cd "$( dirname "$0" )" && pwd )"

[[ -z $operation ]] && operation="dev"
[[ -z $build_id ]] && build_id="none"
[[ -z $event_type ]] && event_type="manual"


jobs_count=`nproc 2>/dev/null`
(( jobs_count += 1 ))
[[ -z $jobs_count ]] && jobs_count="1"

echo "build config:"
echo "operation: $operation"
echo "build_id: $build_id"
echo "event_type: $event_type"
echo

commit_hash=`2>/dev/null git rev-parse HEAD || true`
commit_hash_short=`2>/dev/null git log -1 --pretty=format:%h || true`

if [[ -z $commit_hash || -z $commit_hash_short ]]; then
  echo "failed to detect git commit hash"
  commit_hash="unknown_git_commit"
  commit_hash_short="unknown"
fi

cache_dir="$HOME/.cache/stunneldroid"
if [[ ! -z $STUNNELDROID_BUILD_CACHE_DIR ]]; then
  cache_dir="$STUNNELDROID_BUILD_CACHE_DIR"
fi

echo "using cache directory at $cache_dir"

build_hash=`echo "${commit_hash}${build_id}${event_type}" | sha256sum -t - | cut -f1 -d' '`

cache_stage="$cache_dir/stage_${build_hash}"
cache_status="$cache_dir/status_${build_hash}"

on_error() {
  echo "build failed! (line $1)"
  trap - ERR
  stop_ping
  exit 1
}

trap 'on_error $LINENO' ERR

clean_cache() {
  echo "cleaning up cache"
  mkdir -pv "$cache_stage"
  mkdir -pv "$cache_status"
  rm -rfv "$cache_dir"/*
  touch "$cache_dir/clear"
}

create_pack() {
  local pack_z="$operation.tar.gz"
  local src_parent=`dirname "$script_dir"`
  local src_name=`basename "$script_dir"`
  mkdir -pv "$cache_stage"
  mkdir -pv "$cache_status"
  echo "creating pack: $cache_stage/$pack_z"
  rm -f "$cache_stage/$pack_z"
  echo "creating archive"
  pushd "$src_parent" 1>/dev/null
  tar cf - --exclude="$src_name/.git" --exclude="$src_name/build.sh" --exclude="$src_name/.travis.yml" "$src_name" | pigz -3 - > "$cache_stage/$pack_z"
  popd 1>/dev/null
  echo -n "pack size: "
  stat -c %s "$cache_stage/$pack_z"
  echo "creating stage-completion mark $cache_status/$operation"
  touch "$cache_status/$operation"
}

restore_pack() {
  local operation="$1"
  local pack_z="$operation.tar.gz"
  local src_parent=`dirname "$script_dir"`
  echo "checking stage-completion mark $cache_status/$operation"
  if [[ ! -f "$cache_status/$operation" ]]; then
    echo "no stage-completion mark found at $cache_status/$operation"
    echo "cannot proceed..."
    trap - ERR
    stop_ping
    return 1
  fi
  echo "cleaning up source directory"
  pushd "$script_dir" 1>/dev/null
  for target in * .*
  do
    [[ $target = "." || $target = ".." || $target = ".git" || $target = "build.sh" || $target = ".travis.yml" ]] && continue || true
    echo "removing $target"
    rm -rf "$target"
  done
  popd 1>/dev/null
  echo "extracting pack: $cache_stage/$pack_z"
  pushd "$src_parent" 1>/dev/null
  pigz -c -d "$cache_stage/$pack_z" | tar xf -
  popd 1>/dev/null
  echo "trimming $cache_stage/$pack_z"
  rm "$cache_stage/$pack_z"
  touch "$cache_stage/$pack_z"
}

prepare() {
  . "$script_dir/clean-env.sh.in"
  . "$script_dir/tools/prepare-env.sh.in" "$script_dir/tools"
  echo ""
  echo "*** build environment after performing cleanup"
  export
}

download_stunnel() {
  "$script_dir/stunnel/download.sh"
}

download_android() {
  "$script_dir/tools/prepare.sh"
}

build_stunnel() {
  local assets_basedir="$script_dir/project/app/src/main/assets"
  mkdir -p "$assets_basedir"

  echo ""
  echo "*** building stunnel for armv7 arch ***"
  "$script_dir/stunnel/build.sh" 28 arm "$ndk_bundle_dir" "$ndk_sbs_dir"
  cp "$script_dir/stunnel/build-arm/dist/bin/stunnel" "$assets_basedir/stunnel-arm"

  echo ""
  echo "*** building stunnel for arm64 arch ***"
  "$script_dir/stunnel/build.sh" 28 arm64 "$ndk_bundle_dir" "$ndk_sbs_dir"
  cp "$script_dir/stunnel/build-arm64/dist/bin/stunnel" "$assets_basedir/stunnel-arm64"

  echo ""
  echo "*** building stunnel for x86 arch ***"
  "$script_dir/stunnel/build.sh" 28 x86 "$ndk_bundle_dir" "$ndk_sbs_dir"
  cp "$script_dir/stunnel/build-x86/dist/bin/stunnel" "$assets_basedir/stunnel-x86"

  echo ""
  echo "*** building stunnel for x86_64 arch ***"
  "$script_dir/stunnel/build.sh" 28 x86_64 "$ndk_bundle_dir" "$ndk_sbs_dir"
  cp "$script_dir/stunnel/build-x86_64/dist/bin/stunnel" "$assets_basedir/stunnel-x86_64"
}

build_apk() {
  echo ""
  echo "*** building android project ***"
  pushd 1>/dev/null "$script_dir/project"
  ./gradlew assemble
  popd 1>/dev/null
}

package_build_logs() {
  pushd "$script_dir" 1>/dev/null
  tar cf "build-logs.tar" *.log
  xz -9e "build-logs.tar"
  popd 1>/dev/null
}

if [[ $operation = "download" ]]; then
  run_ping
  clean_cache
  prepare
  download_stunnel 1>"$script_dir/download-stunnel.log" 2>&1 || ( echo "download-stunnel failed! last 200 lines of download-stunnel.log:" && tail -n 200 "$script_dir/download-stunnel.log" && exit 1 )
  download_android 1>"$script_dir/download-android.log" 2>&1 || ( echo "download-android failed! last 200 lines of download-android.log:" && tail -n 200 "$script_dir/download-android.log" && exit 1 )
  create_pack
  stop_ping
elif [[ $operation = "stunnel" ]]; then
  run_ping
  restore_pack "download"
  prepare
  build_stunnel 1>"$script_dir/stunnel.log" 2>&1 || ( echo "build failed! last 200 lines of stunnel.log:" && tail -n 200 "$script_dir/stunnel.log" && exit 1 )
  create_pack
  stop_ping
elif [[ $operation = "apk" ]]; then
  run_ping
  restore_pack "stunnel"
  prepare
  build_apk 1>"$script_dir/project.log" 2>&1 || ( echo "build failed! last 200 lines of project.log:" && tail -n 200 "$script_dir/project.log" && exit 1 )
  #TODO: sign apk
  package_build_logs
  date=`date +"%Y-%m-%d"`
  echo "short commit hash: $commit_hash_short" > "$script_dir/build.info.txt"
  echo " long commit hash: $commit_hash" >> "$script_dir/build.info.txt"
  echo "       build date: $date" >> "$script_dir/build.info.txt"
  stop_ping
elif [[ $operation = "dev" ]]; then
  download_stunnel
  ANDROID_NDK_PATH=""
  build_stunnel
elif [[ $operation = "full_build" ]]; then
  prepare
  download_stunnel
  download_android
  build_stunnel
  build_apk
  #TODO: sign apk
  package_build_logs
  date=`date +"%Y-%m-%d"`
  echo "short commit hash: $commit_hash_short" > "$script_dir/build.info.txt"
  echo " long commit hash: $commit_hash" >> "$script_dir/build.info.txt"
  echo "       build date: $date" >> "$script_dir/build.info.txt"
else
  echo "operation $operation is not supported"
  exit 1
fi


exit 0