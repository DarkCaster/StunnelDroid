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
  echo "usage: build.sh <operation> [build_id] [event type]"
  echo "see invocation examples at .travis.yml"
  exit 2
}

script_dir="$( cd "$( dirname "$0" )" && pwd )"

[[ -z $operation ]] && show_usage
[[ -z $build_id ]] && build_id="none"
[[ -z $event_type ]] && event_type="manual"


jobs_count=`nproc 2>/dev/null`
(( jobs_count += 1 ))
[[ -z $jobs_count ]] && jobs_count="1"

echo "build config:"
echo "operation: $operation"
echp "build_id: $build_id"
echo "event_type: $event_type"
echo

commit_hash=`2>/dev/null git rev-parse HEAD || true`
commit_hash_short=`2>/dev/null git log -1 --pretty=format:%h || true`

if [[ -z $commit_hash || -z $commit_hash_short ]]; then
  echo "failed to detect git commit hash"
  commit_hash="unknown_git_commit"
  commit_hash_short="unknown"
fi

scripts_dir="$script_dir/external/scripts"
configs_dir="$script_dir/external/configs"

cache_dir="$HOME/.cache/stunneldroid"
if [[ ! -z STUNNEL_DROID_BUILD_CACHE_DIR ]]; then
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
  tar cf - --exclude="$src_name/build.sh" --exclude="$src_name/.travis.yml" "$src_name" | pigz -3 - > "$cache_stage/$pack_z"
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
    [[ $target = "." || $target = ".." || $target = "build.sh" || $target = ".travis.yml" ]] && continue || true
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

if [[ $operation = "cleanup" ]]; then
  clean_cache
else
  echo "operation $operation is not supported"
  exit 1
fi
