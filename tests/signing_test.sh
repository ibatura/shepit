#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"

cat > "$T/bin/security" <<'SECURITY'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "find-identity" && "$*" == *" -v "* ]]; then
    printf '%s\n' "${FAKE_IDENTITIES:-}"
elif [[ "$1" == "find-identity" ]]; then
    printf '%s\n' "${FAKE_ALL_IDENTITIES:-}"
elif [[ "$1" == "find-certificate" ]]; then
    printf '%s\n' "${FAKE_CERTS:-}"
else
    echo "unexpected security invocation: $*" >&2
    exit 2
fi
SECURITY
chmod +x "$T/bin/security"
export PATH="$T/bin:$PATH"
source "$REPO/scripts/signing.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

export DICTATION_SIGN_IDENTITY="Foo"
[[ "$(choose_identity)" == "Foo" ]] || fail "explicit identity not selected"
unset DICTATION_SIGN_IDENTITY

export FAKE_IDENTITIES='  1) ABC "Apple Development: a@b.c (TEAM123)"'
[[ "$(choose_identity)" == "Apple Development: a@b.c (TEAM123)" ]] || fail "Apple Development identity not selected"

export FAKE_IDENTITIES='  1) DEF "Shepit Local Signing"'
[[ "$(choose_identity)" == "Shepit Local Signing" ]] || fail "local identity not selected"

# The certificate is there but not listed as valid: sign with it by hash, not with a new one.
export FAKE_IDENTITIES='  0 valid identities found'
export FAKE_CERTS='SHA-1 hash: CA2D0ADE7B95F009071FA5BBC2401CA9DE0CFDA3'
export FAKE_ALL_IDENTITIES='  1) CA2D0ADE7B95F009071FA5BBC2401CA9DE0CFDA3 "Shepit Local Signing" (CSSMERR_TP_NOT_TRUSTED)'
[[ "$(choose_identity)" == "CA2D0ADE7B95F009071FA5BBC2401CA9DE0CFDA3" ]] || fail "existing certificate not reused"
unset FAKE_CERTS FAKE_ALL_IDENTITIES

if choose_identity >/dev/null 2>&1; then
    fail "expected status 3 when no identity exists"
else
    status=$?
    [[ "$status" == 3 ]] || fail "expected status 3, got $status"
fi

echo "signing tests passed"
