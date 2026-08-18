#!/bin/sh
#
# Tests for the index cache and for zig and zls version resolution.
#
# Nothing here touches the network: the index tests write a fixture into a
# scratch cache directory and stamp it fresh, and the zls tests replace
# `fetch_stdout` with a stub. The lookups take a flattened document rather than
# json, so the fixtures below are put through `json_flatten` first.

# The stub functions below are called by the code under test, never directly,
# and the globals set below are read by the sourced zigm, not by this file.
# shellcheck disable=SC2329,SC2034

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# A cut down download index: master and a modern tagged release spell 32 bit
# arm `arm`, 0.13.0 spells it `armv7a` and carries no `version` field, and
# 0.9.0 spells 32 bit x86 `i386`. The macos entry has no shasum.
zigm_write_index() {
    cat >"$1" <<'EOF'
{
  "master": {
    "version": "0.17.0-dev.1778+767d25269",
    "date": "2026-08-16",
    "x86_64-linux": {
      "tarball": "https://example.invalid/zig-master-x86_64.tar.xz",
      "shasum": "1111",
      "size": "1"
    },
    "arm-linux": {
      "tarball": "https://example.invalid/zig-master-arm.tar.xz",
      "shasum": "2222",
      "size": "1"
    }
  },
  "0.15.1": {
    "version": "0.15.1",
    "date": "2025-08-20",
    "x86_64-linux": {
      "tarball": "https://example.invalid/zig-0.15.1-x86_64.tar.xz",
      "shasum": "3333",
      "size": "1"
    },
    "arm-linux": {
      "tarball": "https://example.invalid/zig-0.15.1-arm.tar.xz",
      "shasum": "4444",
      "size": "1"
    }
  },
  "0.13.0": {
    "date": "2024-06-07",
    "x86_64-linux": {
      "tarball": "https://example.invalid/zig-0.13.0-x86_64.tar.xz",
      "shasum": "5555",
      "size": "1"
    },
    "armv7a-linux": {
      "tarball": "https://example.invalid/zig-0.13.0-armv7a.tar.xz",
      "shasum": "6666",
      "size": "1"
    },
    "x86_64-macos": {
      "tarball": "https://example.invalid/zig-0.13.0-macos.tar.xz",
      "size": "1"
    }
  },
  "0.9.0": {
    "date": "2021-12-20",
    "i386-linux": {
      "tarball": "https://example.invalid/zig-0.9.0-i386.tar.xz",
      "shasum": "7777",
      "size": "1"
    }
  }
}
EOF
}

# A literal tab, which is what separates the fields of a flattened document.
zigm_tab=$(printf '\t')

# Flattens a json document given as an argument, so a fixture can stay readable
# as json in the tests that feed one to a lookup.
zigm_flatten() {
    printf '%s\n' "$1" | json_flatten
}

# A zls version selection response, which spells 32 bit arm `armv7a`.
zigm_zls_json='{
  "version": "0.15.0",
  "date": "2025-08-27",
  "x86_64-linux": {
    "tarball": "https://example.invalid/zls-x86_64-linux-0.15.0.tar.xz",
    "shasum": "8888",
    "size": "1"
  },
  "armv7a-linux": {
    "tarball": "https://example.invalid/zls-armv7a-linux-0.15.0.tar.xz",
    "shasum": "9999",
    "size": "1"
  }
}'

# The API reports a pairing it cannot serve as a json object, not as an http
# status, so the message has to be read out of the body.
zigm_zls_error='{"code":3,"message":"ZLS 0.99 has not been released yet"}'

# Points the cache at scratch space and writes a fresh index fixture there, so
# require_index is a cache hit and no download is attempted.
zigm_cache_index() {
    ZIGM_CACHE_DIR="$ZIGM_TMP/cache"
    mkdir -p "$ZIGM_CACHE_DIR"
    zigm_write_index "$ZIGM_CACHE_DIR/index.json"
    date +%s >"$ZIGM_CACHE_DIR/index.json.stamp"
    ZIGM_REFRESH=0
    ZIGM_ARCH=x86_64
    ZIGM_OS=linux

    # Any download here would be a bug in the test or in the cache logic.
    fetch_file() { fail "fetch_file called for $1"; }
}

# ---------------------------------------------------------------------------
# Target keys
# ---------------------------------------------------------------------------

test_target_candidates_are_single_for_stable_arches() {
    assert_out x86_64-linux target_candidates x86_64 linux
    assert_out aarch64-macos target_candidates aarch64 macos
    assert_out riscv64-freebsd target_candidates riscv64 freebsd
}

test_target_candidates_cover_both_arm_spellings() {
    assert_out 'arm-linux
armv7a-linux' target_candidates armv7a linux
    assert_out 'arm-linux
armv7a-linux' target_candidates arm linux
}

test_target_candidates_cover_both_x86_spellings() {
    assert_out 'x86-linux
i386-linux' target_candidates x86 linux
    assert_out 'x86-linux
i386-linux' target_candidates i386 linux
}

test_find_target_picks_the_key_that_is_there() {
    zigm_flat=$(zigm_flatten '{"arm-linux":{},"x86_64-linux":{}}')
    assert_out arm-linux find_target "$zigm_flat" armv7a linux
    assert_out x86_64-linux find_target "$zigm_flat" x86_64 linux
}

test_find_target_falls_back_to_the_old_spelling() {
    assert_out armv7a-linux \
        find_target "$(zigm_flatten '{"armv7a-linux":{}}')" arm linux
    assert_out i386-linux \
        find_target "$(zigm_flatten '{"i386-linux":{}}')" x86 linux
}

test_find_target_fails_when_the_platform_is_missing() {
    assert_fails find_target \
        "$(zigm_flatten '{"x86_64-linux":{}}')" aarch64 macos
    assert_fails find_target 'not flattened' x86_64 linux
}

test_find_target_field_reads_one_field() {
    zigm_flat=$(zigm_flatten \
        '{"x86_64-linux":{"tarball":"https://example.invalid/z.tar.xz"}}')
    assert_out 'https://example.invalid/z.tar.xz' \
        find_target_field "$zigm_flat" x86_64-linux tarball
    assert_fails find_target_field "$zigm_flat" x86_64-linux shasum
    assert_fails find_target_field "$zigm_flat" aarch64-linux tarball
}

# ---------------------------------------------------------------------------
# Index lookups
# ---------------------------------------------------------------------------

test_find_release_reads_an_entry() {
    zigm_write_index "$ZIGM_TMP/index.json"
    zigm_out=$(find_release "$ZIGM_TMP/index.json" 0.15.1)

    # The version is dropped from the front of every path, so the entry reads
    # as a document of its own.
    assert_contains "$zigm_out" "version${zigm_tab}0.15.1" 'the version field'
    assert_contains "$zigm_out" \
        "x86_64-linux${zigm_tab}shasum${zigm_tab}3333" 'a per platform field'
}

test_find_release_fails_on_an_unknown_version() {
    zigm_write_index "$ZIGM_TMP/index.json"
    assert_fails find_release "$ZIGM_TMP/index.json" 0.99.0
}

test_find_release_fails_on_a_broken_index() {
    printf 'not json\n' >"$ZIGM_TMP/broken.json"
    assert_fails find_release "$ZIGM_TMP/broken.json" master
    assert_fails find_release "$ZIGM_TMP/missing.json" master
}

test_find_release_version_prefers_the_field() {
    assert_out 0.17.0-dev.1+abc find_release_version \
        "$(zigm_flatten '{"version":"0.17.0-dev.1+abc"}')" master
    assert_out 0.15.1 find_release_version \
        "$(zigm_flatten '{"version":"0.15.1"}')" 0.15.1
}

test_find_release_version_falls_back_to_the_request() {
    assert_out 0.13.0 find_release_version \
        "$(zigm_flatten '{"date":"2024-06-07"}')" 0.13.0
}

test_find_release_version_needs_a_field_for_master() {
    assert_fails find_release_version \
        "$(zigm_flatten '{"date":"2026-08-16"}')" master
}

# ---------------------------------------------------------------------------
# The zls API url
# ---------------------------------------------------------------------------

test_normalize_query_encodes_plus() {
    assert_out '0.17.0-dev.1778%2B767d25269' \
        normalize_query 0.17.0-dev.1778+767d25269
    assert_out 0.15.1 normalize_query 0.15.1
}

test_zls_url_carries_the_version_and_compatibility() {
    zigm_out=$(zls_url 0.15.1)
    assert_contains "$zigm_out" 'zig_version=0.15.1' 'version'
    assert_contains "$zigm_out" 'compatibility=only-runtime' 'compatibility'
}

test_zls_url_encodes_a_master_version() {
    zigm_out=$(zls_url 0.17.0-dev.1778+767d25269)
    assert_contains "$zigm_out" 'zig_version=0.17.0-dev.1778%2B767d25269' 'version'
}

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

test_parent_dir_strips_the_last_component() {
    assert_out /a/b parent_dir /a/b/c
    assert_out a/b parent_dir a/b/c
    assert_out / parent_dir /c
}

test_parent_dir_handles_a_path_with_no_slash() {
    assert_out . parent_dir index.json
    assert_out . parent_dir --
}

test_find_epoch_is_a_number() {
    zigm_out=$(find_epoch)
    assert_ne '' "$zigm_out" 'epoch'
    case "$zigm_out" in
        *[!0-9]*) fail "epoch is not a number: $zigm_out" ;;
    esac
}

test_cache_fresh_within_the_ttl() {
    printf 'body\n' >"$ZIGM_TMP/c1"
    printf '1000\n' >"$ZIGM_TMP/c1.stamp"
    assert_ok cache_fresh "$ZIGM_TMP/c1" 60 1000
    assert_ok cache_fresh "$ZIGM_TMP/c1" 60 1059
}

test_cache_fresh_past_the_ttl() {
    printf 'body\n' >"$ZIGM_TMP/c2"
    printf '1000\n' >"$ZIGM_TMP/c2.stamp"
    assert_fails cache_fresh "$ZIGM_TMP/c2" 60 1060
    assert_fails cache_fresh "$ZIGM_TMP/c2" 60 9999
}

test_cache_fresh_needs_both_files() {
    printf 'body\n' >"$ZIGM_TMP/c3"
    rm -f "$ZIGM_TMP/c3.stamp"
    assert_fails cache_fresh "$ZIGM_TMP/c3" 60 1000

    printf '1000\n' >"$ZIGM_TMP/c4.stamp"
    assert_fails cache_fresh "$ZIGM_TMP/c4" 60 1000
}

test_cache_fresh_rejects_a_bad_or_future_stamp() {
    printf 'body\n' >"$ZIGM_TMP/c5"

    printf 'yesterday\n' >"$ZIGM_TMP/c5.stamp"
    assert_fails cache_fresh "$ZIGM_TMP/c5" 60 1000

    printf '\n' >"$ZIGM_TMP/c5.stamp"
    assert_fails cache_fresh "$ZIGM_TMP/c5" 60 1000

    # A clock that jumped backwards must not pin a stale file in place.
    printf '2000\n' >"$ZIGM_TMP/c5.stamp"
    assert_fails cache_fresh "$ZIGM_TMP/c5" 60 1000
}

test_fetch_cached_downloads_and_stamps() {
    fetch_file() { printf 'first\n' >"$2"; }
    ZIGM_REFRESH=0

    fetch_cached https://example.invalid/i.json "$ZIGM_TMP/cache/i.json" 3600
    assert_file "$ZIGM_TMP/cache/i.json" 'downloaded file'
    assert_file "$ZIGM_TMP/cache/i.json.stamp" 'stamp'
    assert_eq first "$(cat "$ZIGM_TMP/cache/i.json")" 'body'
}

test_fetch_cached_keeps_a_fresh_copy() {
    fetch_file() { printf 'first\n' >"$2"; }
    ZIGM_REFRESH=0
    fetch_cached https://example.invalid/j.json "$ZIGM_TMP/cache/j.json" 3600

    fetch_file() { printf 'second\n' >"$2"; }
    fetch_cached https://example.invalid/j.json "$ZIGM_TMP/cache/j.json" 3600
    assert_eq first "$(cat "$ZIGM_TMP/cache/j.json")" 'body'
}

test_fetch_cached_refetches_a_stale_copy() {
    fetch_file() { printf 'first\n' >"$2"; }
    ZIGM_REFRESH=0
    fetch_cached https://example.invalid/k.json "$ZIGM_TMP/cache/k.json" 3600

    fetch_file() { printf 'second\n' >"$2"; }
    fetch_cached https://example.invalid/k.json "$ZIGM_TMP/cache/k.json" 0
    assert_eq second "$(cat "$ZIGM_TMP/cache/k.json")" 'body'
}

test_fetch_cached_refresh_ignores_the_cache() {
    fetch_file() { printf 'first\n' >"$2"; }
    ZIGM_REFRESH=0
    fetch_cached https://example.invalid/l.json "$ZIGM_TMP/cache/l.json" 3600

    fetch_file() { printf 'second\n' >"$2"; }
    ZIGM_REFRESH=1
    fetch_cached https://example.invalid/l.json "$ZIGM_TMP/cache/l.json" 3600
    assert_eq second "$(cat "$ZIGM_TMP/cache/l.json")" 'body'
}

test_fetch_cached_leaves_nothing_behind_on_failure() {
    fetch_file() { return 1; }
    ZIGM_REFRESH=0
    assert_status "$ZIGM_EX_ERROR" \
        fetch_cached https://example.invalid/m.json "$ZIGM_TMP/cache/m.json" 3600
    [ ! -f "$ZIGM_TMP/cache/m.json" ] || fail 'a failed download was kept'
}

# ---------------------------------------------------------------------------
# require_zig
# ---------------------------------------------------------------------------

test_require_zig_resolves_a_tagged_release() {
    zigm_cache_index
    require_zig 0.15.1
    assert_eq 0.15.1 "$ZIGM_ZIG_VERSION" 'version'
    assert_eq x86_64-linux "$ZIGM_ZIG_TARGET" 'target'
    assert_eq 'https://example.invalid/zig-0.15.1-x86_64.tar.xz' \
        "$ZIGM_ZIG_TARBALL" 'tarball'
    assert_eq 3333 "$ZIGM_ZIG_SHASUM" 'shasum'
}

test_require_zig_resolves_master_to_a_concrete_version() {
    zigm_cache_index
    require_zig master
    assert_eq 0.17.0-dev.1778+767d25269 "$ZIGM_ZIG_VERSION" 'version'
    assert_eq 'https://example.invalid/zig-master-x86_64.tar.xz' \
        "$ZIGM_ZIG_TARBALL" 'tarball'
}

test_require_zig_uses_the_version_key_when_the_field_is_missing() {
    zigm_cache_index
    require_zig 0.13.0
    assert_eq 0.13.0 "$ZIGM_ZIG_VERSION" 'version'
}

test_require_zig_handles_both_arm_spellings() {
    zigm_cache_index
    ZIGM_ARCH=armv7a

    require_zig master
    assert_eq arm-linux "$ZIGM_ZIG_TARGET" 'modern spelling'

    require_zig 0.13.0
    assert_eq armv7a-linux "$ZIGM_ZIG_TARGET" 'old spelling'
}

test_require_zig_handles_the_old_x86_spelling() {
    zigm_cache_index
    ZIGM_ARCH=x86
    require_zig 0.9.0
    assert_eq i386-linux "$ZIGM_ZIG_TARGET" 'target'
}

test_require_zig_survives_a_missing_shasum() {
    zigm_cache_index
    ZIGM_OS=macos
    require_zig 0.13.0
    assert_eq x86_64-macos "$ZIGM_ZIG_TARGET" 'target'
    assert_eq '' "$ZIGM_ZIG_SHASUM" 'shasum'
}

test_require_zig_dies_on_an_unknown_version() {
    zigm_cache_index
    assert_status "$ZIGM_EX_ERROR" require_zig 0.99.0
    assert_contains "$(require_zig 0.99.0 2>&1)" 'download index' 'message'
}

test_require_zig_dies_when_the_platform_has_no_build() {
    zigm_cache_index
    ZIGM_ARCH=s390x
    assert_status "$ZIGM_EX_ERROR" require_zig 0.15.1
    assert_contains "$(require_zig 0.15.1 2>&1)" 's390x-linux' 'message'
}

# ---------------------------------------------------------------------------
# require_zls
# ---------------------------------------------------------------------------

test_require_zls_resolves_a_pairing() {
    ZIGM_ARCH=x86_64
    ZIGM_OS=linux
    fetch_stdout() { printf '%s\n' "$zigm_zls_json"; }

    require_zls 0.15.1
    assert_eq 0.15.0 "$ZIGM_ZLS_VERSION" 'version'
    assert_eq x86_64-linux "$ZIGM_ZLS_TARGET" 'target'
    assert_eq 'https://example.invalid/zls-x86_64-linux-0.15.0.tar.xz' \
        "$ZIGM_ZLS_TARBALL" 'tarball'
    assert_eq 8888 "$ZIGM_ZLS_SHASUM" 'shasum'
}

test_require_zls_asks_for_the_zig_version() {
    ZIGM_ARCH=x86_64
    ZIGM_OS=linux
    fetch_stdout() {
        printf '%s\n' "$1" >"$ZIGM_TMP/zls-url"
        printf '%s\n' "$zigm_zls_json"
    }

    require_zls 0.17.0-dev.1778+767d25269
    assert_contains "$(cat "$ZIGM_TMP/zls-url")" \
        'zig_version=0.17.0-dev.1778%2B767d25269' 'requested url'
}

test_require_zls_uses_the_old_arm_spelling() {
    ZIGM_ARCH=arm
    ZIGM_OS=linux
    fetch_stdout() { printf '%s\n' "$zigm_zls_json"; }

    require_zls 0.15.1
    assert_eq armv7a-linux "$ZIGM_ZLS_TARGET" 'target'
}

test_require_zls_reports_the_api_message() {
    ZIGM_ARCH=x86_64
    ZIGM_OS=linux
    fetch_stdout() { printf '%s\n' "$zigm_zls_error"; }

    assert_status "$ZIGM_EX_ERROR" require_zls 0.99.0
    assert_contains "$(require_zls 0.99.0 2>&1)" 'has not been released' 'message'
}

test_require_zls_dies_when_the_api_is_unreachable() {
    ZIGM_ARCH=x86_64
    ZIGM_OS=linux
    fetch_stdout() { return 1; }

    assert_status "$ZIGM_EX_ERROR" require_zls 0.15.1
}

test_require_zls_dies_when_the_platform_has_no_build() {
    ZIGM_ARCH=s390x
    ZIGM_OS=linux
    fetch_stdout() { printf '%s\n' "$zigm_zls_json"; }

    assert_status "$ZIGM_EX_ERROR" require_zls 0.15.1
    assert_contains "$(require_zls 0.15.1 2>&1)" 's390x-linux' 'message'
}

# ---------------------------------------------------------------------------
# list-remote
# ---------------------------------------------------------------------------

# Points list-remote at scratch space: a cached index and an empty data
# directory. The downloader check is stubbed out, since a cache hit downloads
# nothing and the command should still run on a machine without curl.
zigm_remote_setup() {
    zigm_cache_index
    ZIGM_VERSIONS_DIR="$ZIGM_TMP/remote/versions"
    ZIGM_CURRENT_LINK="$ZIGM_TMP/remote/current"
    rm -rf "$ZIGM_TMP/remote"
    mkdir -p "$ZIGM_VERSIONS_DIR"
    require_downloader() { :; }
}

test_find_remote_versions_lists_the_builds_for_the_platform() {
    zigm_write_index "$ZIGM_TMP/index.json"
    assert_out '0.17.0-dev.1778+767d25269
0.15.1
0.13.0' find_remote_versions "$ZIGM_TMP/index.json" x86_64 linux
}

test_find_remote_versions_covers_both_spellings_of_an_arch() {
    zigm_write_index "$ZIGM_TMP/index.json"
    assert_out '0.17.0-dev.1778+767d25269
0.15.1
0.13.0' find_remote_versions "$ZIGM_TMP/index.json" armv7a linux
    assert_out 0.9.0 find_remote_versions "$ZIGM_TMP/index.json" x86 linux
}

test_find_remote_versions_skips_a_version_without_a_build() {
    zigm_write_index "$ZIGM_TMP/index.json"
    assert_out 0.13.0 find_remote_versions "$ZIGM_TMP/index.json" x86_64 macos
}

test_find_remote_versions_fails_when_the_platform_has_no_build() {
    zigm_write_index "$ZIGM_TMP/index.json"
    assert_fails find_remote_versions "$ZIGM_TMP/index.json" s390x linux
}

test_find_remote_versions_fails_on_a_broken_index() {
    printf 'not json\n' >"$ZIGM_TMP/broken.json"
    assert_fails find_remote_versions "$ZIGM_TMP/broken.json" x86_64 linux
    assert_fails find_remote_versions "$ZIGM_TMP/missing.json" x86_64 linux
}

test_list_remote_orders_oldest_first_and_names_master() {
    zigm_remote_setup
    assert_out '  0.13.0
  0.15.1
  0.17.0-dev.1778+767d25269 (master)' cmd_list_remote
}

test_list_remote_marks_installed_and_active_versions() {
    zigm_remote_setup
    mkdir -p "$ZIGM_VERSIONS_DIR/0.13.0" "$ZIGM_VERSIONS_DIR/0.15.1"
    swap_link "$ZIGM_VERSIONS_DIR/0.15.1" "$ZIGM_CURRENT_LINK" ||
        fail 'cannot activate 0.15.1'

    assert_out 'i 0.13.0
* 0.15.1
  0.17.0-dev.1778+767d25269 (master)' cmd_list_remote
}

test_list_remote_marks_an_installed_nightly() {
    zigm_remote_setup
    mkdir -p "$ZIGM_VERSIONS_DIR/0.17.0-dev.1778+767d25269"
    assert_out '  0.13.0
  0.15.1
i 0.17.0-dev.1778+767d25269 (master)' cmd_list_remote
}

test_list_remote_dies_when_the_platform_has_no_build() {
    zigm_remote_setup
    ZIGM_ARCH=s390x
    assert_status "$ZIGM_EX_ERROR" cmd_list_remote
    assert_contains "$(cmd_list_remote 2>&1)" 's390x-linux' 'message'
}

test_list_remote_takes_no_arguments() {
    zigm_remote_setup
    assert_status "$ZIGM_EX_USAGE" cmd_list_remote 0.15.1
}

run_tests
