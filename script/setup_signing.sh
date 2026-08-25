#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="Local Development Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

identity_exists() {
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
    | grep -Fq "\"$IDENTITY_NAME\""
}

if identity_exists; then
  printf '%s\n' "$IDENTITY_NAME"
  exit 0
fi

if security find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "certificate exists without a usable private key: $IDENTITY_NAME" >&2
  exit 1
fi

command -v openssl >/dev/null 2>&1 || {
  echo "openssl is required to create the signing identity" >&2
  exit 1
}

umask 077
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

cat >"$TEMP_DIR/openssl.cnf" <<EOF
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no

[subject]
CN = $IDENTITY_NAME
O = Local Development

[extensions]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

openssl req \
  -new -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes \
  -config "$TEMP_DIR/openssl.cnf" \
  -keyout "$TEMP_DIR/private-key.pem" \
  -out "$TEMP_DIR/certificate.pem" \
  >/dev/null 2>&1

P12_PASSWORD="$(openssl rand -hex 24)"
openssl pkcs12 \
  -export -legacy \
  -inkey "$TEMP_DIR/private-key.pem" \
  -in "$TEMP_DIR/certificate.pem" \
  -name "$IDENTITY_NAME" \
  -passout "pass:$P12_PASSWORD" \
  -out "$TEMP_DIR/identity.p12" \
  >/dev/null 2>&1

security import "$TEMP_DIR/identity.p12" \
  -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign \
  >/dev/null

security add-trusted-cert \
  -r trustRoot -p codeSign -k "$KEYCHAIN" \
  "$TEMP_DIR/certificate.pem"

identity_exists || {
  echo "signing identity was imported but is not usable: $IDENTITY_NAME" >&2
  exit 1
}

printf '%s\n' "$IDENTITY_NAME"
