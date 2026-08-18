#!/bin/sh
#
# Tests for tool detection.
#
# `have` is replaced with a stub driven by ZIGM_FAKE_HAVE, so the results do
# not depend on what happens to be installed on the machine running the tests.
# Detection branches that also run the tool stub the tool itself.

# The stub functions below are called by the code under test, never directly.
# shellcheck disable=SC2329

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

ZIGM_FAKE_HAVE=''

have() {
    for zigm_fake in $ZIGM_FAKE_HAVE; do
        if [ "$zigm_fake" = "$1" ]; then
            return 0
        fi
    done
    return 1
}

test_find_downloader_prefers_curl() {
    ZIGM_FAKE_HAVE='curl wget'
    assert_out curl find_downloader
}

test_find_downloader_falls_back_to_wget() {
    ZIGM_FAKE_HAVE='wget'
    assert_out wget find_downloader
}

test_find_downloader_fails_without_either() {
    ZIGM_FAKE_HAVE='tar xz'
    assert_fails find_downloader
}

test_find_xz_prefers_the_xz_binary() {
    ZIGM_FAKE_HAVE='xz tar'
    assert_out xz find_xz
}

test_find_xz_accepts_a_tar_with_xz_support() {
    ZIGM_FAKE_HAVE='tar'
    tar() { printf '  -J, --xz  filter through xz\n'; }
    assert_out tar find_xz
}

test_find_xz_rejects_a_tar_without_xz_support() {
    ZIGM_FAKE_HAVE='tar'
    tar() { printf '  -z, --gzip  filter through gzip\n'; }
    assert_fails find_xz
}

test_find_xz_fails_without_tar() {
    ZIGM_FAKE_HAVE='curl'
    assert_fails find_xz
}

test_find_sha256_preference_order() {
    ZIGM_FAKE_HAVE='sha256sum shasum openssl cksum'
    assert_out sha256sum find_sha256

    ZIGM_FAKE_HAVE='shasum openssl cksum'
    assert_out shasum find_sha256

    ZIGM_FAKE_HAVE='openssl cksum'
    assert_out openssl find_sha256
}

test_find_sha256_accepts_a_cksum_with_algorithms() {
    ZIGM_FAKE_HAVE='cksum'
    cksum() { return 0; }
    assert_out cksum find_sha256
}

test_find_sha256_rejects_a_cksum_without_algorithms() {
    ZIGM_FAKE_HAVE='cksum'
    cksum() { return 1; }
    assert_fails find_sha256
}

test_find_sha256_fails_without_any_tool() {
    ZIGM_FAKE_HAVE='curl tar xz'
    assert_fails find_sha256
}

test_require_downloader_sets_the_global() {
    ZIGM_FAKE_HAVE='curl'
    require_downloader
    assert_eq curl "$ZIGM_DOWNLOADER" 'downloader'
}

test_require_downloader_dies_without_one() {
    ZIGM_FAKE_HAVE=''
    assert_status "$ZIGM_EX_ERROR" require_downloader
}

test_require_extractor_dies_without_tar() {
    ZIGM_FAKE_HAVE='xz'
    assert_status "$ZIGM_EX_ERROR" require_extractor
}

test_require_extractor_dies_without_xz() {
    ZIGM_FAKE_HAVE='tar'
    tar() { printf '  -z, --gzip  filter through gzip\n'; }
    assert_status "$ZIGM_EX_ERROR" require_extractor
}

test_require_extractor_sets_the_global() {
    ZIGM_FAKE_HAVE='tar xz'
    require_extractor
    assert_eq xz "$ZIGM_XZ" 'xz method'
}

test_require_sha256_sets_the_global() {
    ZIGM_FAKE_HAVE='shasum'
    require_sha256 2>/dev/null
    assert_eq shasum "$ZIGM_SHA256" 'sha256 tool'
}

test_require_sha256_warns_but_survives() {
    ZIGM_FAKE_HAVE=''
    require_sha256 2>"$ZIGM_TMP/warn"
    assert_eq 0 "$?" 'exit status'
    assert_eq '' "$ZIGM_SHA256" 'sha256 tool'
    assert_contains "$(cat "$ZIGM_TMP/warn")" 'will not be verified' 'warning'
}

run_tests
