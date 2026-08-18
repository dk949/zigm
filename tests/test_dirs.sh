#!/bin/sh
#
# Tests for directory resolution.

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# The XDG variables leak in from whoever runs the tests, so every test that
# cares sets them explicitly.
unset XDG_DATA_HOME XDG_CACHE_HOME XDG_CONFIG_HOME XDG_STATE_HOME

test_base_dir_macos() {
    assert_out '/u/Library/Application Support/zigm' base_dir data macos /u
    assert_out '/u/Library/Application Support/zigm' base_dir config macos /u
    assert_out '/u/Library/Application Support/zigm' base_dir state macos /u
    assert_out '/u/Library/Caches/zigm' base_dir cache macos /u
}

test_base_dir_macos_ignores_xdg() {
    XDG_DATA_HOME=/xdg/data
    export XDG_DATA_HOME
    assert_out '/u/Library/Application Support/zigm' base_dir data macos /u
}

test_base_dir_xdg_defaults() {
    assert_out '/u/.local/share/zigm' base_dir data linux /u
    assert_out '/u/.cache/zigm' base_dir cache linux /u
    assert_out '/u/.config/zigm' base_dir config linux /u
    assert_out '/u/.local/state/zigm' base_dir state linux /u
}

test_base_dir_xdg_overrides() {
    XDG_DATA_HOME=/xdg/data
    XDG_CACHE_HOME=/xdg/cache
    XDG_CONFIG_HOME=/xdg/config
    XDG_STATE_HOME=/xdg/state
    export XDG_DATA_HOME XDG_CACHE_HOME XDG_CONFIG_HOME XDG_STATE_HOME
    assert_out '/xdg/data/zigm' base_dir data linux /u
    assert_out '/xdg/cache/zigm' base_dir cache linux /u
    assert_out '/xdg/config/zigm' base_dir config linux /u
    assert_out '/xdg/state/zigm' base_dir state linux /u
}

test_base_dir_treats_bsd_as_xdg() {
    assert_out '/u/.local/share/zigm' base_dir data freebsd /u
    assert_out '/u/.local/share/zigm' base_dir data openbsd /u
}

test_base_dir_needs_a_home() {
    assert_fails base_dir data linux ''
    assert_fails base_dir data macos ''
}

test_base_dir_rejects_unknown_kind() {
    assert_fails base_dir nonsense linux /u
    assert_fails base_dir nonsense macos /u
}

test_require_dirs_honors_overrides() {
    ZIGM_OS=linux
    ZIGM_DATA_DIR=/d
    ZIGM_CACHE_DIR=/c
    ZIGM_CONFIG_DIR=/k
    ZIGM_STATE_DIR=/s
    require_dirs
    assert_eq /d "$ZIGM_DATA_DIR" 'data dir'
    assert_eq /c "$ZIGM_CACHE_DIR" 'cache dir'
    assert_eq /k "$ZIGM_CONFIG_DIR" 'config dir'
    assert_eq /s "$ZIGM_STATE_DIR" 'state dir'
}

test_require_dirs_derives_from_home() {
    ZIGM_OS=linux
    HOME=/u
    unset ZIGM_DATA_DIR ZIGM_CACHE_DIR ZIGM_CONFIG_DIR ZIGM_STATE_DIR
    require_dirs
    assert_eq '/u/.local/share/zigm' "$ZIGM_DATA_DIR" 'data dir'
    assert_eq '/u/.cache/zigm' "$ZIGM_CACHE_DIR" 'cache dir'
    assert_eq '/u/.config/zigm' "$ZIGM_CONFIG_DIR" 'config dir'
    assert_eq '/u/.local/state/zigm' "$ZIGM_STATE_DIR" 'state dir'
}

test_require_dirs_derives_paths_inside_the_data_dir() {
    ZIGM_OS=linux
    ZIGM_DATA_DIR=/d
    ZIGM_CACHE_DIR=/c
    ZIGM_CONFIG_DIR=/k
    ZIGM_STATE_DIR=/s
    require_dirs
    assert_eq /d/versions "$ZIGM_VERSIONS_DIR" 'versions dir'
    assert_eq /d/current "$ZIGM_CURRENT_LINK" 'current link'
    assert_eq /s/previous "$ZIGM_PREVIOUS_FILE" 'previous record'
}

test_require_dirs_dies_without_home() {
    ZIGM_OS=linux
    HOME=''
    unset ZIGM_DATA_DIR ZIGM_CACHE_DIR ZIGM_CONFIG_DIR ZIGM_STATE_DIR
    assert_status "$ZIGM_EX_ERROR" require_dirs
}

test_ensure_dirs_creates_what_is_missing() {
    ZIGM_OS=linux
    ZIGM_DATA_DIR="$ZIGM_TMP/ensure/data"
    ZIGM_CACHE_DIR="$ZIGM_TMP/ensure/cache"
    ZIGM_CONFIG_DIR="$ZIGM_TMP/ensure/config"
    ZIGM_STATE_DIR="$ZIGM_TMP/ensure/state"
    require_dirs
    ensure_dirs
    assert_dir "$ZIGM_VERSIONS_DIR" 'versions dir'
    assert_dir "$ZIGM_CACHE_DIR" 'cache dir'
    assert_dir "$ZIGM_STATE_DIR" 'state dir'
}

test_ensure_dirs_is_repeatable() {
    # shellcheck disable=SC2034 # require_dirs reads ZIGM_OS.
    ZIGM_OS=linux
    ZIGM_DATA_DIR="$ZIGM_TMP/twice/data"
    ZIGM_CACHE_DIR="$ZIGM_TMP/twice/cache"
    ZIGM_CONFIG_DIR="$ZIGM_TMP/twice/config"
    ZIGM_STATE_DIR="$ZIGM_TMP/twice/state"
    require_dirs
    ensure_dirs
    assert_ok ensure_dirs
}

run_tests
