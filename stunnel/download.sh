#!/bin/bash
#

set -e

#script base directory
script_dir="$(cd "$(dirname "$0")" && pwd)"

#base url
stunnel_base_url="https://www.stunnel.org/downloads"
openssl_base_url="https://www.openssl.org/source"

#get filename from checksum files
stunnel_checksum="stunnel.checksum"
stunnel_filename=$(awk '{print $2}' "$script_dir/$stunnel_checksum")

openssl_checksum="openssl.checksum"
openssl_filename=$(awk '{print $2}' "$script_dir/$openssl_checksum")

check_integrity() {
  #check integrity
  pushd 1>/dev/null "$script_dir"
  result=true
  sha256sum -c "$1" || result=false
  popd 1>/dev/null
  [[ $result = true ]] && return 0 || return 1
}

#download source archives
if [[ ! -f "$script_dir/$stunnel_filename" ]] || ! check_integrity "$stunnel_checksum" ; then
  rm -fv "$script_dir/$stunnel_filename"
  wget -O "$script_dir/$stunnel_filename" "$stunnel_base_url/$stunnel_filename"
  check_integrity "$stunnel_checksum"
fi

if [[ ! -f "$script_dir/$openssl_filename" ]] || ! check_integrity "$openssl_checksum" ; then
  rm -fv "$script_dir/$openssl_filename"
  wget -O "$script_dir/$openssl_filename" "$openssl_base_url/$openssl_filename"
  check_integrity "$openssl_checksum"
fi
