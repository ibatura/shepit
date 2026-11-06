#!/usr/bin/env bash
set -euo pipefail

choose_identity() {
    if [[ -n "${DICTATION_SIGN_IDENTITY:-}" ]]; then
        printf '%s\n' "$DICTATION_SIGN_IDENTITY"
        return 0
    fi

    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    local identity
    identity="$(printf '%s\n' "$identities" | /usr/bin/sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p' | /usr/bin/head -n 1)"
    if [[ -n "$identity" ]]; then
        printf '%s\n' "$identity"
        return 0
    fi

    identity="$(printf '%s\n' "$identities" | /usr/bin/sed -nE 's/.*"(Shepit Local Signing)".*/\1/p' | /usr/bin/head -n 1)"
    if [[ -n "$identity" ]]; then
        printf '%s\n' "$identity"
        return 0
    fi

    # The certificate can be in the keychain without showing as valid (its trust setting not applied).
    # Sign with it anyway, by its hash: a new certificate would make macOS forget Shepit's permissions.
    identity="$(security find-certificate -a -c "Shepit Local Signing" -Z 2>/dev/null \
        | /usr/bin/sed -nE 's/^SHA-1 hash: ([0-9A-F]+)$/\1/p' | /usr/bin/head -n 1 || true)"
    if [[ -n "$identity" ]] && security find-identity -p codesigning 2>/dev/null | /usr/bin/grep -q "$identity"; then
        printf '%s\n' "$identity"
        return 0
    fi

    return 3
}

ensure_self_signed() (
    local temp_dir
    temp_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/shepit-signing.XXXXXX")"
    trap '/bin/rm -rf "$temp_dir"' EXIT

    printf '%s\n' "Creating Shepit Local Signing. macOS will ask for your login password once."

    /usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
        -subj "/CN=Shepit Local Signing" \
        -addext "extendedKeyUsage=critical,codeSigning" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "basicConstraints=critical,CA:false" \
        -keyout "$temp_dir/key.pem" -out "$temp_dir/cert.pem"
    p12_pass="$(/usr/bin/openssl rand -hex 16)"
    /usr/bin/openssl pkcs12 -export -out "$temp_dir/signing.p12" \
        -inkey "$temp_dir/key.pem" -in "$temp_dir/cert.pem" \
        -passout "pass:$p12_pass"
    /usr/bin/security import "$temp_dir/signing.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P "$p12_pass" -T /usr/bin/codesign
    /usr/bin/security add-trusted-cert -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" \
        "$temp_dir/cert.pem"
)
