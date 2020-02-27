#!/bin/bash
#

set -e

#script base directory
script_dir="$(cd "$(dirname "$0")" && pwd)"

#base url
tools_base_url="https://dl.google.com/android/repository"
jdk_base_url="https://download.java.net/java/GA/jdk13.0.2/d4173c853231432d94f001e99d882ca7/8/GPL"

#get filename from checksum files
tools_checksum="tools.checksum"
tools_filename=$(awk '{print $2}' "$script_dir/$tools_checksum")

jdk_checksum="jdk.checksum"
jdk_filename=$(awk '{print $2}' "$script_dir/$jdk_checksum")

check_integrity() {
  #check integrity
  pushd 1>/dev/null "$script_dir"
  result=true
  sha256sum -c "$1" || result=false
  popd 1>/dev/null
  [[ $result = true ]] && return 0 || return 1
}

#download source archive
if [[ ! -f "$script_dir/$tools_filename" ]] || ! check_integrity "$tools_checksum" ; then
  rm -fv "$script_dir/$tools_filename"
  wget -O "$script_dir/$tools_filename" "$tools_base_url/$tools_filename"
  check_integrity "$tools_checksum"
fi

if [[ ! -f "$script_dir/$jdk_filename" ]] || ! check_integrity "$jdk_checksum" ; then
  rm -fv "$script_dir/$jdk_filename"
  wget -O "$script_dir/$jdk_filename" "$jdk_base_url/$jdk_filename"
  check_integrity "$jdk_checksum"
fi
