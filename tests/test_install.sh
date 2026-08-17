#!/bin/sh
#
# Tests for install and update.
#
# Nothing here touches the network: the index is written into a scratch cache
# directory and stamped fresh, `fetch_file` is replaced with a stub serving
# tarballs built on the fly, and `fetch_stdout` answers for the zls API. The
# tarballs are real, so tar and xz do the same work they do in an install.
# Building one needs a compressor, which is a separate question from the
# decompressor zigm picks: see zigm_find_packer below.

# The stub functions below are called by the code under test, never directly,
# and the globals set below are read by the sourced zigm, not by this file.
# shellcheck disable=SC2329,SC2034

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# zigm_write_file <path> <content>
#
# Writes an executable stub or a plain file, creating the directory above it.
zigm_write_file() {
    mkdir -p "$(parent_dir "$1")" || fail "cannot create the parent of $1"
    printf '%s\n' "$2" >"$1" || fail "cannot write $1"
}

# zigm_can_pack <xz command>
#
# True when that xz compresses as well as decompresses. busybox's applet only
# decompresses, which is all zigm needs but not all the fixtures need.
zigm_can_pack() {
    printf 'probe\n' | "$1" -c 2>/dev/null | "$1" -dc 2>/dev/null |
        grep -q '^probe$'
}

# zigm_tar_can_pack
#
# True when tar can compress with -J on its own.
zigm_tar_can_pack() {
    zigm_probe=$ZIGM_TMP/packer
    rm -rf "$zigm_probe"
    mkdir -p "$zigm_probe/dir" || return 1
    printf 'probe\n' >"$zigm_probe/dir/file" || return 1
    (cd "$zigm_probe" && tar -cJf probe.tar.xz dir) 2>/dev/null &&
        (cd "$zigm_probe" && tar -tJf probe.tar.xz) >/dev/null 2>&1
}

# Prints how to build a tar.xz: an xz that compresses, named by path, or `tar`
# when tar's own -J does the job. ZIGM_XZ says nothing about this, since it is
# picked for decompression alone, and under busybox the two differ.
zigm_find_packer() {
    zigm_can_pack xz && {
        printf 'xz\n'
        return 0
    }

    # busybox's shell reaches its own applets before PATH, so an xz that does
    # compress has to be named by path to be reached at all.
    zigm_ifs=$IFS
    IFS=:
    for zigm_dir in $PATH; do
        IFS=$zigm_ifs
        if [ -x "$zigm_dir/xz" ] && zigm_can_pack "$zigm_dir/xz"; then
            printf '%s\n' "$zigm_dir/xz"
            return 0
        fi
        IFS=:
    done
    IFS=$zigm_ifs

    zigm_tar_can_pack && {
        printf 'tar\n'
        return 0
    }

    return 1
}

# Probed once, since every fixture build needs it. An empty value means nothing
# here can compress, which zigm_make_fixtures reports.
zigm_packer=$(zigm_find_packer) || zigm_packer=''

# zigm_pack <output> <directory> <entry>
#
# Builds a tar.xz of one entry of a directory, the way upstream ships one.
zigm_pack() {
    case "$zigm_packer" in
        '') return 1 ;;
        tar) (cd "$2" && tar -cJf "$1" "$3") ;;
        *) (cd "$2" && tar -cf - "$3") | "$zigm_packer" -c >"$1" ;;
    esac
}

# Builds the two tarballs and records their checksums. The zig one holds a
# single top level directory, as zig's do, and the zls one holds its files
# directly, as zls's do. Both carry a LICENSE, which is what the install has to
# keep the zls tarball from landing on.
zigm_make_fixtures() {
    zigm_fix="$ZIGM_TMP/fixtures"
    rm -rf "$zigm_fix"

    zigm_write_file "$zigm_fix/zig/zig-x86_64-linux-0.15.1/zig" '#!/bin/sh'
    chmod +x "$zigm_fix/zig/zig-x86_64-linux-0.15.1/zig"
    zigm_write_file "$zigm_fix/zig/zig-x86_64-linux-0.15.1/lib/std.zig" '// std'
    zigm_write_file "$zigm_fix/zig/zig-x86_64-linux-0.15.1/LICENSE" 'zig license'

    zigm_write_file "$zigm_fix/zls/zls" '#!/bin/sh'
    chmod +x "$zigm_fix/zls/zls"
    zigm_write_file "$zigm_fix/zls/LICENSE" 'zls license'
    zigm_write_file "$zigm_fix/zls/README.md" 'zls readme'

    [ -n "$zigm_packer" ] ||
        fail 'no xz that compresses found, install xz or a tar with -J'

    zigm_pack "$zigm_fix/zig.tar.xz" "$zigm_fix/zig" zig-x86_64-linux-0.15.1 ||
        fail 'cannot build the zig fixture tarball'
    zigm_pack "$zigm_fix/zls.tar.xz" "$zigm_fix/zls" . ||
        fail 'cannot build the zls fixture tarball'

    if [ -n "$ZIGM_SHA256" ]; then
        zigm_zig_sha=$(find_checksum "$ZIGM_SHA256" "$zigm_fix/zig.tar.xz")
        zigm_zls_sha=$(find_checksum "$ZIGM_SHA256" "$zigm_fix/zls.tar.xz")
    else
        zigm_zig_sha=''
        zigm_zls_sha=''
    fi
}

# zigm_write_index <path>
#
# A cut down download index naming the fixture tarballs, with a tagged release
# and a master entry that both resolve to the same build.
zigm_write_index() {
    cat >"$1" <<EOF
{
  "master": {
    "version": "0.17.0-dev.1778+767d25269",
    "date": "2026-08-16",
    "x86_64-linux": {
      "tarball": "https://example.invalid/zig-master-x86_64.tar.xz",
      "shasum": "$zigm_zig_sha",
      "size": "1"
    }
  },
  "0.15.1": {
    "version": "0.15.1",
    "date": "2025-08-20",
    "x86_64-linux": {
      "tarball": "https://example.invalid/zig-0.15.1-x86_64.tar.xz",
      "shasum": "$zigm_zig_sha",
      "size": "1"
    }
  }
}
EOF
}

# The zls pairing, answered by the fetch_stdout stub.
zigm_zls_json() {
    cat <<EOF
{
  "version": "0.15.0",
  "date": "2025-08-27",
  "x86_64-linux": {
    "tarball": "https://example.invalid/zls-x86_64-linux-0.15.0.tar.xz",
    "shasum": "$zigm_zls_sha",
    "size": "1"
  }
}
EOF
}

# The downloader stub, serving the fixtures by url.
zigm_fetch_file() {
    case "$1" in
        *index.json) zigm_write_index "$2" ;;
        *zig-*.tar.xz) cp "$zigm_fix/zig.tar.xz" "$2" ;;
        *zls-*.tar.xz) cp "$zigm_fix/zls.tar.xz" "$2" ;;
        *) fail "unexpected download: $1" ;;
    esac
}

# Points the install at scratch space, builds the fixtures, and stubs out both
# halves of the network. The cached index is stamped fresh, so only a tarball,
# or a `update` that refreshes on purpose, reaches the downloader stub.
zigm_install_setup() {
    zigm_root="$ZIGM_TMP/install"
    rm -rf "$zigm_root"

    ZIGM_DATA_DIR="$zigm_root"
    ZIGM_VERSIONS_DIR="$zigm_root/versions"
    ZIGM_CURRENT_LINK="$zigm_root/current"
    ZIGM_CACHE_DIR="$zigm_root/cache"
    mkdir -p "$ZIGM_VERSIONS_DIR" "$ZIGM_CACHE_DIR"

    ZIGM_ARCH=x86_64
    ZIGM_OS=linux
    ZIGM_NO_ZLS=0
    ZIGM_FORCE=0
    ZIGM_REFRESH=0
    # info and note would otherwise land in the test report.
    ZIGM_QUIET=1

    ZIGM_SHA256=$(find_sha256) || ZIGM_SHA256=''
    ZIGM_XZ=$(find_xz) || ZIGM_XZ=''
    [ -n "$ZIGM_XZ" ] || fail 'no xz support found, cannot build the fixtures'

    zigm_make_fixtures
    zigm_write_index "$ZIGM_CACHE_DIR/index.json"
    date +%s >"$ZIGM_CACHE_DIR/index.json.stamp"

    fetch_file() { zigm_fetch_file "$@"; }
    fetch_stdout() { zigm_zls_json; }

    # Nothing is downloaded for real, so the tests run on a machine with no
    # curl. tar, xz, and jq are used for real, and are checked above.
    require_downloader() { :; }
}

# Fails the test when the install left scratch state behind.
assert_no_scratch() {
    for zigm_leftover in "$ZIGM_VERSIONS_DIR"/.new-* "$ZIGM_VERSIONS_DIR"/.old-*; do
        [ ! -e "$zigm_leftover" ] || fail "scratch left behind: $zigm_leftover"
    done
}

# ---------------------------------------------------------------------------
# Checksums
# ---------------------------------------------------------------------------

# The sha256 of the five bytes `zigm` and a newline.
zigm_known_sha='fc1aad32e827564f62e9bb7b76451182b7ba9a3cb9396a4bb6d18ab4ab7a4767'

test_find_checksum_matches_a_known_digest() {
    zigm_tool=$(find_sha256) || return 0
    printf 'zigm\n' >"$ZIGM_TMP/sum-input"
    assert_out "$zigm_known_sha" find_checksum "$zigm_tool" "$ZIGM_TMP/sum-input"
}

test_find_checksum_agrees_across_the_tools() {
    printf 'zigm\n' >"$ZIGM_TMP/sum-input"
    for zigm_tool in sha256sum shasum openssl cksum; do
        have "$zigm_tool" || continue
        zigm_out=$(find_checksum "$zigm_tool" "$ZIGM_TMP/sum-input") || continue
        assert_eq "$zigm_known_sha" "$zigm_out" "$zigm_tool digest"
    done
}

test_find_checksum_fails_on_an_unknown_tool() {
    printf 'zigm\n' >"$ZIGM_TMP/sum-input"
    assert_fails find_checksum md5sum "$ZIGM_TMP/sum-input"
    assert_fails find_checksum sha256sum "$ZIGM_TMP/nowhere"
}

test_verify_download_accepts_a_matching_checksum() {
    ZIGM_SHA256=$(find_sha256) || return 0
    printf 'zigm\n' >"$ZIGM_TMP/verify-input"
    assert_ok verify_download "$ZIGM_TMP/verify-input" "$zigm_known_sha" 'zig 0.15.1'
}

test_verify_download_ignores_the_case_of_the_checksum() {
    ZIGM_SHA256=$(find_sha256) || return 0
    printf 'zigm\n' >"$ZIGM_TMP/verify-input"
    zigm_upper=$(printf '%s\n' "$zigm_known_sha" | tr '[:lower:]' '[:upper:]')
    assert_ok verify_download "$ZIGM_TMP/verify-input" "$zigm_upper" 'zig 0.15.1'
}

test_verify_download_dies_on_a_mismatch() {
    ZIGM_SHA256=$(find_sha256) || return 0
    printf 'zigm\n' >"$ZIGM_TMP/verify-input"
    assert_status "$ZIGM_EX_ERROR" \
        verify_download "$ZIGM_TMP/verify-input" "${zigm_known_sha%??}00" 'zig 0.15.1'
    assert_contains "$(verify_download "$ZIGM_TMP/verify-input" 0000 x 2>&1)" \
        'checksum mismatch' 'message'
}

test_verify_download_warns_rather_than_dies_without_a_checksum() {
    ZIGM_SHA256=$(find_sha256) || return 0
    printf 'zigm\n' >"$ZIGM_TMP/verify-input"
    assert_ok verify_download "$ZIGM_TMP/verify-input" '' 'zig 0.15.1'
    assert_contains "$(verify_download "$ZIGM_TMP/verify-input" '' 'zig 0.15.1' 2>&1)" \
        'not verified' 'warning'
}

test_verify_download_is_a_no_op_without_a_tool() {
    ZIGM_SHA256=''
    printf 'other\n' >"$ZIGM_TMP/verify-input"
    assert_ok verify_download "$ZIGM_TMP/verify-input" "$zigm_known_sha" 'zig 0.15.1'
}

# ---------------------------------------------------------------------------
# Unpacking
# ---------------------------------------------------------------------------

test_find_extract_root_strips_a_single_directory() {
    zigm_dir="$ZIGM_TMP/root-one"
    mkdir -p "$zigm_dir/zig-x86_64-linux-0.15.1"
    assert_out "$zigm_dir/zig-x86_64-linux-0.15.1" find_extract_root "$zigm_dir"
}

test_find_extract_root_keeps_a_directory_of_files() {
    zigm_dir="$ZIGM_TMP/root-flat"
    mkdir -p "$zigm_dir"
    : >"$zigm_dir/zls"
    assert_out "$zigm_dir" find_extract_root "$zigm_dir"

    : >"$zigm_dir/LICENSE"
    assert_out "$zigm_dir" find_extract_root "$zigm_dir"
}

test_find_extract_root_keeps_a_directory_of_several_entries() {
    zigm_dir="$ZIGM_TMP/root-many"
    mkdir -p "$zigm_dir/lib"
    : >"$zigm_dir/zig"
    assert_out "$zigm_dir" find_extract_root "$zigm_dir"
}

test_find_extract_root_fails_on_nothing_to_take() {
    mkdir -p "$ZIGM_TMP/root-empty"
    assert_fails find_extract_root "$ZIGM_TMP/root-empty"
    assert_fails find_extract_root "$ZIGM_TMP/root-missing"
}

test_move_contents_moves_everything_across() {
    zigm_src="$ZIGM_TMP/move-src"
    zigm_dst="$ZIGM_TMP/move-dst"
    mkdir -p "$zigm_src/lib" "$zigm_dst"
    : >"$zigm_src/zig"
    : >"$zigm_src/lib/std.zig"

    assert_ok move_contents "$zigm_src" "$zigm_dst"
    assert_file "$zigm_dst/zig" 'moved file'
    assert_file "$zigm_dst/lib/std.zig" 'moved directory'
}

test_move_contents_replaces_a_name_that_is_taken() {
    zigm_src="$ZIGM_TMP/replace-src"
    zigm_dst="$ZIGM_TMP/replace-dst"
    mkdir -p "$zigm_src" "$zigm_dst"
    printf 'new\n' >"$zigm_src/LICENSE"
    printf 'old\n' >"$zigm_dst/LICENSE"

    assert_ok move_contents "$zigm_src" "$zigm_dst"
    assert_eq new "$(cat "$zigm_dst/LICENSE")" 'replaced file'
}

test_move_contents_fails_on_an_empty_or_missing_directory() {
    mkdir -p "$ZIGM_TMP/move-empty" "$ZIGM_TMP/move-into"
    assert_fails move_contents "$ZIGM_TMP/move-empty" "$ZIGM_TMP/move-into"
    assert_fails move_contents "$ZIGM_TMP/move-nowhere" "$ZIGM_TMP/move-into"
    assert_fails move_contents "$ZIGM_TMP/move-empty" "$ZIGM_TMP/move-nowhere"
}

test_unpack_tarball_unpacks_what_upstream_ships() {
    zigm_install_setup
    mkdir -p "$zigm_root/unpack"
    assert_ok unpack_tarball "$zigm_fix/zig.tar.xz" "$zigm_root/unpack"
    assert_file "$zigm_root/unpack/zig-x86_64-linux-0.15.1/zig" 'unpacked binary'
    assert_file "$zigm_root/unpack/zig-x86_64-linux-0.15.1/lib/std.zig" 'unpacked lib'
}

# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------

test_install_lays_out_zig_and_zls_together() {
    zigm_install_setup
    install_version 0.15.1 1

    zigm_dir="$ZIGM_VERSIONS_DIR/0.15.1"
    [ -x "$zigm_dir/zig" ] || fail 'the zig binary is not there'
    [ -x "$zigm_dir/zls" ] || fail 'the zls binary is not there'
    assert_file "$zigm_dir/lib/std.zig" "zig's lib directory"
    assert_no_scratch
}

test_install_takes_only_the_binary_out_of_the_zls_tarball() {
    zigm_install_setup
    install_version 0.15.1 1

    # A real zls tarball ships a LICENSE and a README beside the binary, and
    # neither may land on zig's.
    assert_eq 'zig license' \
        "$(cat "$ZIGM_VERSIONS_DIR/0.15.1/LICENSE")" 'LICENSE'
    [ ! -e "$ZIGM_VERSIONS_DIR/0.15.1/README.md" ] ||
        fail "the zls tarball's README was installed"
}

test_install_dies_when_the_tarball_holds_no_zls() {
    zigm_install_setup
    zigm_write_file "$zigm_fix/nozls/README.md" 'no binary here'
    zigm_pack "$zigm_fix/zls.tar.xz" "$zigm_fix/nozls" . ||
        fail 'cannot build the fixture tarball'
    zigm_zls_sha=''

    assert_status "$ZIGM_EX_ERROR" install_version 0.15.1 1
    [ ! -d "$ZIGM_VERSIONS_DIR/0.15.1" ] || fail 'a bad tarball was installed'
}

test_install_keeps_no_tarball_around() {
    zigm_install_setup
    install_version 0.15.1 1

    zigm_out=$(find "$zigm_root" -name '*.tar.xz' 2>/dev/null)
    assert_eq '' "$zigm_out" 'tarballs left behind'
}

test_install_activates_the_version() {
    zigm_install_setup
    install_version 0.15.1 1
    assert_out 0.15.1 find_link_version "$ZIGM_CURRENT_LINK"
}

test_install_leaves_the_link_alone_when_told_not_to_use_it() {
    zigm_install_setup
    install_version 0.15.1 0
    [ ! -L "$ZIGM_CURRENT_LINK" ] || fail 'the link was created'
    assert_dir "$ZIGM_VERSIONS_DIR/0.15.1" 'installed version'
}

test_install_resolves_master_to_its_version_directory() {
    zigm_install_setup
    install_version master 1
    assert_dir "$ZIGM_VERSIONS_DIR/0.17.0-dev.1778+767d25269" 'nightly'
    assert_out 0.17.0-dev.1778+767d25269 find_link_version "$ZIGM_CURRENT_LINK"
}

test_install_skips_zls_when_asked() {
    zigm_install_setup
    ZIGM_NO_ZLS=1
    # A pairing must not even be asked for, since the answer would be thrown
    # away, and the API may well have none to give for a fresh nightly.
    fetch_stdout() { fail 'the zls API was queried'; }

    install_version 0.15.1 1 2>/dev/null

    [ -x "$ZIGM_VERSIONS_DIR/0.15.1/zig" ] || fail 'the zig binary is not there'
    [ ! -e "$ZIGM_VERSIONS_DIR/0.15.1/zls" ] || fail 'zls was installed anyway'
}

test_install_warns_that_zls_was_skipped() {
    zigm_install_setup
    ZIGM_NO_ZLS=1
    fetch_stdout() { fail 'the zls API was queried'; }
    assert_contains "$(install_version 0.15.1 1 2>&1)" 'zls was skipped' 'warning'
}

test_install_leaves_an_installed_version_alone() {
    zigm_install_setup
    install_version 0.15.1 0
    printf 'kept\n' >"$ZIGM_VERSIONS_DIR/0.15.1/marker"

    # A second install downloads nothing at all, not even the zls pairing.
    fetch_file() { fail "downloaded $1"; }
    fetch_stdout() { fail 'the zls API was queried'; }

    install_version 0.15.1 1 2>/dev/null
    assert_file "$ZIGM_VERSIONS_DIR/0.15.1/marker" 'untouched install'
    # It still ends up active, so `install` names what `current` points at.
    assert_out 0.15.1 find_link_version "$ZIGM_CURRENT_LINK"
}

test_install_leaves_an_installed_version_alone_without_a_pairing() {
    zigm_install_setup
    install_version 0.15.1 0

    # The pairing the version was installed with is gone from the API, which
    # must not stand in the way of a version that is already there.
    fetch_stdout() { printf '%s\n' '{"code":0,"message":"no zls"}'; }

    assert_ok install_version 0.15.1 1
    assert_out 0.15.1 find_link_version "$ZIGM_CURRENT_LINK"
}

test_install_does_not_warn_about_zls_on_an_installed_version() {
    zigm_install_setup
    install_version 0.15.1 0
    ZIGM_NO_ZLS=1
    ZIGM_QUIET=0

    zigm_out=$(install_version 0.15.1 0 2>&1)
    assert_not_contains "$zigm_out" 'zls was skipped' 'warning'
    assert_contains "$zigm_out" 'already installed' 'note'
}

test_install_records_the_zls_it_installed() {
    zigm_install_setup
    install_version 0.15.1 0
    assert_out 'zls 0.15.0' find_zls_note "$ZIGM_VERSIONS_DIR/0.15.1"
}

test_install_records_that_no_zls_was_installed() {
    zigm_install_setup
    ZIGM_NO_ZLS=1
    fetch_stdout() { fail 'the zls API was queried'; }

    install_version 0.15.1 0 2>/dev/null
    assert_file "$ZIGM_VERSIONS_DIR/0.15.1/.zigm" 'the record'
    assert_out 'no zls' find_zls_note "$ZIGM_VERSIONS_DIR/0.15.1"
}

test_install_adds_a_zls_a_version_is_missing() {
    zigm_install_setup
    ZIGM_NO_ZLS=1
    install_version 0.15.1 0 2>/dev/null
    printf 'kept\n' >"$ZIGM_VERSIONS_DIR/0.15.1/marker"

    # The zig tarball is not fetched again, since the version itself is left
    # exactly as it was.
    ZIGM_NO_ZLS=0
    fetch_file() {
        case "$1" in
            *zig-*) fail "downloaded $1" ;;
            *) zigm_fetch_file "$@" ;;
        esac
    }

    install_version 0.15.1 0 2>/dev/null
    [ -x "$ZIGM_VERSIONS_DIR/0.15.1/zls" ] || fail 'zls was not added'
    assert_file "$ZIGM_VERSIONS_DIR/0.15.1/marker" 'untouched install'
    assert_file "$ZIGM_VERSIONS_DIR/0.15.1/lib/std.zig" "zig's lib directory"
    assert_out 'zls 0.15.0' find_zls_note "$ZIGM_VERSIONS_DIR/0.15.1"
    assert_no_scratch
}

test_install_keeps_the_zls_tarballs_extras_off_an_existing_version() {
    zigm_install_setup
    ZIGM_NO_ZLS=1
    install_version 0.15.1 0 2>/dev/null

    ZIGM_NO_ZLS=0
    install_version 0.15.1 0 2>/dev/null

    assert_eq 'zig license' \
        "$(cat "$ZIGM_VERSIONS_DIR/0.15.1/LICENSE")" 'LICENSE'
    [ ! -e "$ZIGM_VERSIONS_DIR/0.15.1/README.md" ] ||
        fail "the zls tarball's README was installed"
}

test_install_leaves_a_version_alone_when_adding_its_zls_fails() {
    zigm_install_setup
    ZIGM_NO_ZLS=1
    install_version 0.15.1 0 2>/dev/null

    ZIGM_NO_ZLS=0
    fetch_file() {
        case "$1" in
            *zls-*) return 1 ;;
            *) zigm_fetch_file "$@" ;;
        esac
    }

    assert_status "$ZIGM_EX_ERROR" install_version 0.15.1 0
    [ ! -e "$ZIGM_VERSIONS_DIR/0.15.1/zls" ] || fail 'a failed download installed zls'
    assert_file "$ZIGM_VERSIONS_DIR/0.15.1/zig" 'the version itself'
    assert_no_scratch
}

test_install_says_a_version_is_already_installed() {
    zigm_install_setup
    ZIGM_QUIET=0
    install_version 0.15.1 0 >/dev/null 2>&1
    assert_contains "$(install_version 0.15.1 0 2>&1)" 'already installed' 'note'
}

test_install_replaces_the_version_when_forced() {
    zigm_install_setup
    install_version 0.15.1 0
    printf 'stale\n' >"$ZIGM_VERSIONS_DIR/0.15.1/marker"

    ZIGM_FORCE=1
    install_version 0.15.1 1
    [ ! -e "$ZIGM_VERSIONS_DIR/0.15.1/marker" ] || fail 'the old install was kept'
    [ -x "$ZIGM_VERSIONS_DIR/0.15.1/zig" ] || fail 'the zig binary is not there'
    assert_no_scratch
}

test_install_dies_on_a_checksum_mismatch() {
    zigm_install_setup
    [ -n "$ZIGM_SHA256" ] || return 0

    # An index whose shasums name a different file than the stub serves.
    zigm_zig_sha="$zigm_known_sha"
    zigm_zls_sha="$zigm_known_sha"
    zigm_write_index "$ZIGM_CACHE_DIR/index.json"

    assert_status "$ZIGM_EX_ERROR" install_version 0.15.1 1
    [ ! -d "$ZIGM_VERSIONS_DIR/0.15.1" ] || fail 'a bad download was installed'
}

test_install_dies_when_the_tarball_holds_no_zig() {
    zigm_install_setup
    zigm_write_file "$zigm_fix/empty/notzig" 'nothing useful'
    zigm_pack "$zigm_fix/zig.tar.xz" "$zigm_fix/empty" . ||
        fail 'cannot build the fixture tarball'
    zigm_zig_sha=''
    zigm_write_index "$ZIGM_CACHE_DIR/index.json"

    assert_status "$ZIGM_EX_ERROR" install_version 0.15.1 1
    [ ! -d "$ZIGM_VERSIONS_DIR/0.15.1" ] || fail 'a bad tarball was installed'
}

test_install_keeps_the_old_version_when_a_forced_reinstall_fails() {
    zigm_install_setup
    install_version 0.15.1 0
    printf 'kept\n' >"$ZIGM_VERSIONS_DIR/0.15.1/marker"

    # The download fails partway through the second install.
    fetch_file() {
        case "$1" in
            *zls-*) return 1 ;;
            *) zigm_fetch_file "$@" ;;
        esac
    }
    ZIGM_FORCE=1

    assert_status "$ZIGM_EX_ERROR" install_version 0.15.1 0
    assert_file "$ZIGM_VERSIONS_DIR/0.15.1/marker" 'the old install'
    assert_no_scratch
}

test_install_leaves_no_scratch_when_it_fails() {
    zigm_install_setup
    zigm_write_file "$zigm_fix/empty/notzig" 'nothing useful'
    zigm_pack "$zigm_fix/zig.tar.xz" "$zigm_fix/empty" . ||
        fail 'cannot build the fixture tarball'
    zigm_zig_sha=''
    zigm_write_index "$ZIGM_CACHE_DIR/index.json"

    assert_status "$ZIGM_EX_ERROR" install_version 0.15.1 1
    assert_no_scratch
}

# ---------------------------------------------------------------------------
# Reclaiming install scratch
#
# The signal handlers only exit, so what they reach is the EXIT handler these
# cover. Delivering a real signal is left untested, since a test cannot signal
# the subshell it runs its subject in without naming a pid the shell does not
# hand out.
# ---------------------------------------------------------------------------

# Writes a scratch pair for a version, and the version directory when asked.
zigm_fake_scratch() {
    mkdir -p "$ZIGM_VERSIONS_DIR/.new-$1/root" ||
        fail 'cannot create the new scratch directory'
    mkdir -p "$ZIGM_VERSIONS_DIR/.old-$1" || fail 'cannot create the old one'
    printf 'old\n' >"$ZIGM_VERSIONS_DIR/.old-$1/marker" ||
        fail 'cannot mark the old install'

    [ "${2:-0}" -eq 1 ] || return 0
    mkdir -p "$ZIGM_VERSIONS_DIR/$1" || fail "cannot create the $1 directory"
    printf 'new\n' >"$ZIGM_VERSIONS_DIR/$1/marker" ||
        fail 'cannot mark the new install'
}

test_reclaim_scratch_puts_a_version_back_when_it_never_arrived() {
    zigm_install_setup
    zigm_fake_scratch 0.15.1 0

    assert_ok reclaim_scratch 0.15.1
    assert_out 'old' cat "$ZIGM_VERSIONS_DIR/0.15.1/marker"
    assert_no_scratch
}

test_reclaim_scratch_drops_the_old_copy_when_the_new_one_is_there() {
    zigm_install_setup
    zigm_fake_scratch 0.15.1 1

    assert_ok reclaim_scratch 0.15.1
    assert_out 'new' cat "$ZIGM_VERSIONS_DIR/0.15.1/marker"
    assert_no_scratch
}

test_reclaim_scratch_says_it_put_a_version_back() {
    zigm_install_setup
    zigm_fake_scratch 0.16.0 0
    assert_contains "$(reclaim_scratch 0.16.0 2>&1)" 'put zig 0.16.0 back' 'warning'
}

test_reclaim_scratch_is_a_no_op_with_nothing_to_reclaim() {
    zigm_install_setup
    assert_ok reclaim_scratch 0.15.1
    [ ! -e "$ZIGM_VERSIONS_DIR/0.15.1" ] || fail 'a version was invented'
}

test_sweep_scratch_reclaims_every_version_it_finds() {
    zigm_install_setup
    zigm_fake_scratch 0.15.1 0
    zigm_fake_scratch 0.16.0 1
    mkdir -p "$ZIGM_VERSIONS_DIR/.new-0.14.0" || fail 'cannot create the third'

    assert_ok sweep_scratch
    assert_out 'old' cat "$ZIGM_VERSIONS_DIR/0.15.1/marker"
    assert_out 'new' cat "$ZIGM_VERSIONS_DIR/0.16.0/marker"
    assert_no_scratch
}

test_sweep_scratch_leaves_installed_versions_alone() {
    zigm_install_setup
    install_version 0.15.1 0
    assert_ok sweep_scratch
    [ -x "$ZIGM_VERSIONS_DIR/0.15.1/zig" ] || fail 'an install was swept away'
}

test_sweep_scratch_is_a_no_op_on_an_empty_versions_directory() {
    zigm_install_setup
    assert_ok sweep_scratch
    assert_out '' find_versions "$ZIGM_VERSIONS_DIR"
}

# ---------------------------------------------------------------------------
# update
# ---------------------------------------------------------------------------

test_update_installs_the_current_master() {
    zigm_install_setup
    cmd_update
    assert_dir "$ZIGM_VERSIONS_DIR/0.17.0-dev.1778+767d25269" 'nightly'
    assert_no_scratch
}

test_update_refetches_the_index() {
    zigm_install_setup
    # A stale index that would otherwise be used, since it is stamped fresh.
    printf 'not json\n' >"$ZIGM_CACHE_DIR/index.json"
    cmd_update
    assert_dir "$ZIGM_VERSIONS_DIR/0.17.0-dev.1778+767d25269" 'nightly'
}

test_update_activates_the_new_nightly_when_a_nightly_was_active() {
    zigm_install_setup
    mkdir -p "$ZIGM_VERSIONS_DIR/0.17.0-dev.1+aaa"
    swap_link "$ZIGM_VERSIONS_DIR/0.17.0-dev.1+aaa" "$ZIGM_CURRENT_LINK" ||
        fail 'cannot activate the old nightly'

    cmd_update
    assert_out 0.17.0-dev.1778+767d25269 find_link_version "$ZIGM_CURRENT_LINK"
}

test_update_leaves_a_pinned_release_active() {
    zigm_install_setup
    mkdir -p "$ZIGM_VERSIONS_DIR/0.15.1"
    swap_link "$ZIGM_VERSIONS_DIR/0.15.1" "$ZIGM_CURRENT_LINK" ||
        fail 'cannot activate the release'

    cmd_update
    assert_dir "$ZIGM_VERSIONS_DIR/0.17.0-dev.1778+767d25269" 'nightly'
    assert_out 0.15.1 find_link_version "$ZIGM_CURRENT_LINK"
}

test_update_activates_when_nothing_was_active() {
    zigm_install_setup
    cmd_update
    assert_out 0.17.0-dev.1778+767d25269 find_link_version "$ZIGM_CURRENT_LINK"
}

test_update_is_repeatable() {
    zigm_install_setup
    cmd_update
    printf 'kept\n' >"$ZIGM_VERSIONS_DIR/0.17.0-dev.1778+767d25269/marker"

    fetch_file() {
        case "$1" in
            *.tar.xz) fail "downloaded $1" ;;
            *) zigm_fetch_file "$@" ;;
        esac
    }

    cmd_update
    assert_file "$ZIGM_VERSIONS_DIR/0.17.0-dev.1778+767d25269/marker" \
        'untouched install'
}

# ---------------------------------------------------------------------------
# Command line
#
# These run the script as a program, and every one of them fails before
# anything is downloaded.
# ---------------------------------------------------------------------------

test_install_needs_exactly_one_version() {
    assert_status "$ZIGM_EX_USAGE" zigm_run install
    assert_status "$ZIGM_EX_USAGE" zigm_run install --no-zls
    assert_status "$ZIGM_EX_USAGE" zigm_run install 0.15.1 0.14.1
}

test_install_rejects_an_unknown_option() {
    assert_status "$ZIGM_EX_USAGE" zigm_run install --nope 0.15.1
    assert_contains "$(zigm_run_out install --nope 0.15.1)" 'unknown option' 'message'
}

test_install_rejects_a_version_reaching_out_of_the_versions_directory() {
    assert_status "$ZIGM_EX_USAGE" zigm_run install ../elsewhere
    assert_status "$ZIGM_EX_USAGE" zigm_run install .partial
}

test_update_takes_no_version() {
    assert_status "$ZIGM_EX_USAGE" zigm_run update 0.15.1
    assert_status "$ZIGM_EX_USAGE" zigm_run update --nope
}

test_help_lists_the_install_options() {
    zigm_help=$(zigm_run --help)
    for zigm_opt in --no-zls --no-use --force; do
        assert_contains "$zigm_help" "$zigm_opt" 'install options'
    done
}

run_tests
