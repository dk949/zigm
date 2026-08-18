#!/bin/sh
#
# Tests for the config file: its parser, the lookups over what it parsed, the
# precedence against the environment, and the whole read as one command sees
# it. Nothing here touches the network.

# The globals set below are read by the sourced zigm, not by this file.
# shellcheck disable=SC2034

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# A tab, since a test compares against the shape normalize_config prints.
zigm_tab=$(printf '\t')

# write_config <line>...
#
# Writes a config file where zigm_run looks for one, creating the directory
# the first time. The scratch space is shared by every test in the file, so a
# test that writes one clears it again with clear_config.
write_config() {
    mkdir -p "$ZIGM_TMP/config" || fail "cannot create the config directory"
    : >"$ZIGM_TMP/config/zigm.conf" || fail "cannot write the config file"
    for zigm_line in "$@"; do
        printf '%s\n' "$zigm_line" >>"$ZIGM_TMP/config/zigm.conf" ||
            fail 'cannot write the config file'
    done
}

clear_config() {
    rm -f "$ZIGM_TMP/config/zigm.conf" || fail 'cannot remove the config file'
}

# ---------------------------------------------------------------------------
# normalize_config
# ---------------------------------------------------------------------------

test_normalize_config_reads_a_setting() {
    assert_out "retries${zigm_tab}5" normalize_config 'retries = 5'
}

test_normalize_config_ignores_space_around_a_setting() {
    assert_out "retries${zigm_tab}5" normalize_config '   retries=5   '
    assert_out "retries${zigm_tab}5" normalize_config 'retries	=	5'
}

test_normalize_config_keeps_space_inside_a_value() {
    assert_out "alias.work${zigm_tab}a b" normalize_config 'alias.work = a b'
}

test_normalize_config_drops_comments_and_blank_lines() {
    assert_out "retries${zigm_tab}5" normalize_config '# a comment

retries = 5 # and a trailing one
'
}

test_normalize_config_reads_an_empty_file_as_no_settings() {
    assert_out '' normalize_config ''
    assert_out '' normalize_config '# nothing but a comment'
}

test_normalize_config_reads_every_line() {
    assert_out "retries${zigm_tab}5
index_ttl${zigm_tab}60" normalize_config 'retries = 5
index_ttl = 60'
}

test_normalize_config_takes_a_dotted_key() {
    assert_out "alias.work${zigm_tab}0.15.1" normalize_config 'alias.work = 0.15.1'
}

test_normalize_config_takes_an_empty_value() {
    assert_out "retries${zigm_tab}" normalize_config 'retries ='
}

test_normalize_config_fails_on_a_line_without_a_value() {
    assert_fails normalize_config 'retries'
}

test_normalize_config_fails_on_a_key_it_cannot_read() {
    assert_fails normalize_config '2retries = 5'
    assert_fails normalize_config 'two words = 5'
    assert_fails normalize_config '= 5'
}

test_normalize_config_names_the_bad_line() {
    zigm_out=$(normalize_config '# one
retries = 5
nonsense' 2>&1)
    assert_contains "$zigm_out" 'line 3' 'the line number'
    assert_contains "$zigm_out" 'nonsense' 'the line'
}

test_normalize_config_prints_nothing_when_a_line_is_bad() {
    zigm_out=$(normalize_config 'retries = 5
nonsense' 2>/dev/null)
    assert_not_contains "$zigm_out" "retries${zigm_tab}5" 'a setting'
}

# ---------------------------------------------------------------------------
# The lookups
# ---------------------------------------------------------------------------

test_config_field_reads_a_value() {
    assert_out 5 config_field "retries${zigm_tab}5" retries
}

test_config_field_fails_on_a_missing_key() {
    assert_fails config_field "retries${zigm_tab}5" index_ttl
    assert_fails config_field '' retries
}

test_config_field_finds_an_empty_value() {
    assert_out '' config_field "retries${zigm_tab}" retries
}

test_config_field_takes_the_later_of_two() {
    assert_out 7 config_field "retries${zigm_tab}5
retries${zigm_tab}7" retries
}

test_config_keys_lists_the_keys_in_order() {
    assert_out 'retries
index_ttl' config_keys "retries${zigm_tab}5
index_ttl${zigm_tab}60"
}

test_config_keys_lists_nothing_for_no_settings() {
    assert_out '' config_keys ''
}

# ---------------------------------------------------------------------------
# Precedence
# ---------------------------------------------------------------------------

test_config_settle_falls_back_to_the_defaults() {
    ZIGM_CONFIG_TEXT=''
    unset ZIGM_RETRIES ZIGM_RETRY_DELAY ZIGM_CONNECT_TIMEOUT ZIGM_INDEX_TTL
    config_settle
    assert_eq 2 "$ZIGM_RETRIES" 'retries'
    assert_eq 1 "$ZIGM_RETRY_DELAY" 'retry delay'
    assert_eq 15 "$ZIGM_CONNECT_TIMEOUT" 'connect timeout'
    assert_eq 3600 "$ZIGM_INDEX_TTL" 'index ttl'
}

test_config_settle_takes_the_file_over_a_default() {
    ZIGM_CONFIG_TEXT="retries${zigm_tab}5"
    unset ZIGM_RETRIES ZIGM_INDEX_TTL
    config_settle
    assert_eq 5 "$ZIGM_RETRIES" 'retries'
    assert_eq 3600 "$ZIGM_INDEX_TTL" 'a key the file leaves out'
}

test_config_settle_takes_the_environment_over_the_file() {
    ZIGM_CONFIG_TEXT="retries${zigm_tab}5"
    ZIGM_RETRIES=9
    config_settle
    assert_eq 9 "$ZIGM_RETRIES" 'retries'
}

test_config_settle_refuses_a_value_of_the_wrong_shape() {
    ZIGM_CONFIG_FILE=/nowhere/zigm.conf
    ZIGM_CONFIG_TEXT="retries${zigm_tab}soon"
    unset ZIGM_RETRIES
    assert_status "$ZIGM_EX_ERROR" config_settle
}

test_config_settle_refuses_an_empty_value() {
    ZIGM_CONFIG_FILE=/nowhere/zigm.conf
    ZIGM_CONFIG_TEXT="retries${zigm_tab}"
    unset ZIGM_RETRIES
    assert_status "$ZIGM_EX_ERROR" config_settle
}

test_config_settle_leaves_an_environment_value_alone() {
    ZIGM_CONFIG_FILE=/nowhere/zigm.conf
    ZIGM_CONFIG_TEXT="retries${zigm_tab}soon"
    ZIGM_RETRIES=9
    config_settle
    assert_eq 9 "$ZIGM_RETRIES" 'retries'
}

# ---------------------------------------------------------------------------
# require_config
# ---------------------------------------------------------------------------

test_require_config_settles_the_defaults_without_a_file() {
    ZIGM_CONFIG_DIR="$ZIGM_TMP/empty-config"
    unset ZIGM_RETRIES
    require_config
    assert_eq "$ZIGM_TMP/empty-config/zigm.conf" "$ZIGM_CONFIG_FILE" 'the path'
    assert_eq '' "$ZIGM_CONFIG_TEXT" 'the settings'
    assert_eq 2 "$ZIGM_RETRIES" 'retries'
}

test_require_config_reads_the_file() {
    write_config 'retries = 5'
    ZIGM_CONFIG_DIR="$ZIGM_TMP/config"
    unset ZIGM_RETRIES
    require_config
    assert_eq 5 "$ZIGM_RETRIES" 'retries'
    clear_config
}

test_require_config_warns_about_an_unknown_key() {
    write_config 'retries = 5' 'nonsense = 1'
    ZIGM_CONFIG_DIR="$ZIGM_TMP/config"
    unset ZIGM_RETRIES
    # The capture runs in a subshell, so the globals are read back from a
    # second call rather than from that one.
    zigm_out=$(require_config 2>&1 >/dev/null)
    assert_contains "$zigm_out" "unknown key 'nonsense'" 'the warning'
    require_config 2>/dev/null
    assert_eq 5 "$ZIGM_RETRIES" 'the known key beside it'
    clear_config
}

test_require_config_dies_on_a_line_it_cannot_read() {
    write_config 'nonsense'
    ZIGM_CONFIG_DIR="$ZIGM_TMP/config"
    assert_status "$ZIGM_EX_ERROR" require_config
    clear_config
}

# ---------------------------------------------------------------------------
# End to end
# ---------------------------------------------------------------------------

test_run_reads_a_value_from_the_file() {
    write_config 'retries = 5'
    assert_contains "$(zigm_run_out -v list)" 'retries=5, from the file' 'the debug line'
    clear_config
}

test_run_names_the_file_it_read() {
    write_config 'retries = 5'
    assert_contains "$(zigm_run_out -v list)" "config file: $ZIGM_TMP/config/zigm.conf" 'the path'
    clear_config
}

test_run_says_when_there_is_no_file() {
    clear_config
    assert_contains "$(zigm_run_out -v list)" 'config file: none at' 'the note'
}

test_run_warns_about_an_unknown_key() {
    write_config 'nonsense = 1'
    assert_contains "$(zigm_run_out list)" "unknown key 'nonsense'" 'the warning'
    assert_status 0 zigm_run list
    clear_config
}

test_run_fails_on_a_bad_line() {
    write_config 'nonsense'
    assert_status "$ZIGM_EX_ERROR" zigm_run list
    assert_contains "$(zigm_run_out list)" 'line 1' 'the line number'
    clear_config
}

test_run_fails_on_a_bad_value() {
    write_config 'retries = soon'
    assert_status "$ZIGM_EX_ERROR" zigm_run list
    assert_contains "$(zigm_run_out list)" 'wants a whole number' 'the reason'
    clear_config
}

run_tests
