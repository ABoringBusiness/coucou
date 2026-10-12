#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-crypto-accounts.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library NotchBuddy/Sources/App/CryptoAccounts.swift \
    tests/CryptoAccountsTests.swift -o "$TEST_DIR/crypto-accounts-tests"
"$TEST_DIR/crypto-accounts-tests"
