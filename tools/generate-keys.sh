#!/bin/bash
#

set -e

#script base directory
script_dir="$(cd "$(dirname "$0")" && pwd)"
. "$script_dir/prepare-env.sh.in" "$script_dir"

echo "Generating new keystore"
rm -rf "$KEYSTORE_DIR"
mkdir -p "$KEYSTORE_DIR"
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 24 | head -n 1 >"$KEYSTORE_DIR/password_keystore"
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 24 | head -n 1 >"$KEYSTORE_DIR/password_key"

which 2>/dev/null 1>&2 keytool || export PATH="$JAVA_HOME/bin:$PATH"

keytool -genkeypair -v \
  -storetype JKS -keystore "$KEYSTORE_DIR/keystore" -alias apk_sign_key \
  -keyalg RSA -keysize 4096 -validity 50000 \
  -storepass:file "$KEYSTORE_DIR/password_keystore" \
  -keypass:file "$KEYSTORE_DIR/password_key" \
  -dname "CN=John Doe, OU=None, O=NA, L=NA, ST=NA, C=NA"

echo "New build keys generated at $KEYSTORE_DIR. Make backup of this directory for later builds."
