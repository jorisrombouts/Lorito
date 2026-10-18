#!/bin/sh
# One-time: create a self-signed code-signing certificate "Lorito Dev" in the login keychain.
# Ad-hoc signatures change on every rebuild, so macOS forgets the Accessibility grant each time.
# A fixed certificate gives the app a stable identity; grant Accessibility once, keep it across rebuilds.
# Run from a terminal (it prompts for your login password to trust the certificate).
set -eu
TMP=$(mktemp -d)
cd "$TMP"
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=Lorito Dev" -addext "keyUsage=digitalSignature" -addext "extendedKeyUsage=codeSigning"
openssl pkcs12 -export -inkey key.pem -in cert.pem -out lorito.p12 -passout pass:lorito -name "Lorito Dev" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1   # macOS cannot import OpenSSL 3 defaults
security import lorito.p12 -k ~/Library/Keychains/login.keychain-db -P lorito -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
rm -rf "$TMP"
security find-identity -v -p codesigning | grep "Lorito Dev" && echo "done: ./build-app.sh will now sign with it"
