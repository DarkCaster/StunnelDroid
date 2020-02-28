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

[[ -z $operation ]] && operation="full_build"
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
if [[ ! -z $STUNNEL_DROID_BUILD_CACHE_DIR ]]; then
  cache_dir="$STUNNEL_DROID_BUILD_CACHE_DIR"
fi

echo "using cache directory at $cache_dir"

build_hash=`echo "${commit_hash}${build_id}${event_type}" | sha256sum -t - | cut -f1 -d' '`

cache_stage="$cache_dir/stage_${build_hash}"
cache_status="$cache_dir/status_${build_hash}"

mkdir -pv "$cache_stage"
mkdir -pv "$cache_status"

on_error() {
  echo "build failed! (line $1)"
  trap - ERR
  stop_ping
  exit 1
}

trap 'on_error $LINENO' ERR

clean_cache() {
  echo "cleaning up cache"
  rm -rfv "$cache_dir"/*
  touch "$cache_dir/clear"
}

create_pack() {
  local pack_z="$operation.tar.gz"
  local src_parent=`dirname "$script_dir"`
  local src_name=`basename "$script_dir"`
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
  #TODO:
  #clean_env
  prepare_script_dir="$script_dir/tools"
  . "$prepare_script_dir/prepare-env.sh.in"
}

download() {
  "$script_dir/stunnel/download.sh"
  "$script_dir/tools/prepare.sh"
}

build_stunnel() {
  "$script_dir/stunnel/build.sh" 28 arm "$ANDROID_NDK_PATH"
  "$script_dir/stunnel/build.sh" 28 arm64 "$ANDROID_NDK_PATH"
  "$script_dir/stunnel/build.sh" 28 x86 "$ANDROID_NDK_PATH"
  "$script_dir/stunnel/build.sh" 28 x86_64 "$ANDROID_NDK_PATH"
}

if [[ $operation = "download" ]]; then
  run_ping
  clean_cache
  prepare
  download 1>"$script_dir/download.log" 2>&1 || ( echo "download failed! last 200 lines of download.log:" && tail -n 200 "$script_dir/download.log" && exit 1 )
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
  stop_ping
elif [[ $operation = "full_build" ]]; then
  prepare
  download
  build_stunnel
else
  echo "operation $operation is not supported"
  exit 1
fi


exit 0