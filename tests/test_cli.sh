#!/bin/sh
#
# End to end tests: these run the script as a program under the shell being
# tested, in a scratch HOME with the directory overrides pointed at scratch
# space. Only commands that need no external tools are exercised here, so the
# results do not depend on curl or jq being installed.

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

test_help_exits_zero() {
    assert_status 0 zigm_run --help
    assert_status 0 zigm_run -h
}

test_help_lists_the_commands() {
    zigm_help=$(zigm_run --help)
    assert_contains "$zigm_help" 'usage:' 'usage line'
    for zigm_cmd in install use uninstall list list-remote which current \
        update clean; do
        assert_contains "$zigm_help" "$zigm_cmd" 'command list'
    done
}

test_help_describes_one_command() {
    zigm_help=$(zigm_run install --help)
    assert_contains "$zigm_help" 'usage: zigm install' 'install usage line'
    assert_contains "$zigm_help" '--no-zls' 'install option'
    assert_contains "$zigm_help" "zigm --help" 'pointer to the global options'
}

test_command_help_is_taken_from_anywhere_on_the_line() {
    assert_eq "$(zigm_run install --help)" "$(zigm_run -h install)" \
        'help either side of the command'
}

test_command_help_exits_zero_for_every_command() {
    for zigm_cmd in install use uninstall list list-remote which current \
        update clean; do
        assert_status 0 zigm_run "$zigm_cmd" --help
    done
}

test_command_help_needs_no_state() {
    # The help comes before any work, so a command that would otherwise fail
    # without an active version still prints it.
    assert_status 0 zigm_run current --help
    assert_status 0 zigm_run which --help
}

test_help_for_an_unknown_command_is_a_usage_error() {
    assert_status "$ZIGM_EX_USAGE" zigm_run frobnicate --help
    assert_contains "$(zigm_run_out frobnicate --help)" 'unknown command' \
        'message'
}

test_global_flags_are_taken_after_the_command() {
    zigm_out=$(zigm_run_out list -v)
    assert_contains "$zigm_out" 'zigm: debug: platform:' 'platform debug line'

    assert_status 0 zigm_run list --refresh
    assert_eq '' "$(zigm_run_out list --quiet)" 'quiet output'
}

test_a_global_flag_never_reaches_the_command() {
    # use fails because the version is not installed, an error rather than the
    # usage error an unparsed -v would have caused.
    assert_status "$ZIGM_EX_ERROR" zigm_run use -v 0.15.1
    assert_status "$ZIGM_EX_ERROR" zigm_run use 0.15.1 -v
}

test_an_unknown_option_after_the_command_is_the_commands_own() {
    assert_status "$ZIGM_EX_USAGE" zigm_run install 0.15.1 --nope
    assert_contains "$(zigm_run_out install 0.15.1 --nope)" \
        "unknown option '--nope' for install" 'message'
}

test_a_flag_does_not_swallow_a_later_argument() {
    # list still sees `extra`, so its argument count check fails.
    assert_status "$ZIGM_EX_USAGE" zigm_run list extra --verbose
    assert_status "$ZIGM_EX_USAGE" zigm_run list --verbose extra
}

test_version_prints_the_version() {
    assert_out "$ZIGM_VERSION" zigm_run --version
    assert_out "$ZIGM_VERSION" zigm_run -V
}

test_no_arguments_is_a_usage_error() {
    assert_status "$ZIGM_EX_USAGE" zigm_run
    assert_contains "$(zigm_run_out)" 'usage:' 'usage on stderr'
}

test_unknown_option_is_a_usage_error() {
    assert_status "$ZIGM_EX_USAGE" zigm_run --nope
    assert_contains "$(zigm_run_out --nope)" 'unknown option' 'message'
}

test_unknown_command_is_a_usage_error() {
    assert_status "$ZIGM_EX_USAGE" zigm_run frobnicate
    assert_contains "$(zigm_run_out frobnicate)" 'unknown command' 'message'
}

test_wrong_argument_counts_are_usage_errors() {
    assert_status "$ZIGM_EX_USAGE" zigm_run install
    assert_status "$ZIGM_EX_USAGE" zigm_run install 0.15.1 extra
    assert_status "$ZIGM_EX_USAGE" zigm_run use
    assert_status "$ZIGM_EX_USAGE" zigm_run uninstall
    assert_status "$ZIGM_EX_USAGE" zigm_run list extra
    assert_status "$ZIGM_EX_USAGE" zigm_run list-remote extra
    assert_status "$ZIGM_EX_USAGE" zigm_run current extra
    assert_status "$ZIGM_EX_USAGE" zigm_run update extra
    assert_status "$ZIGM_EX_USAGE" zigm_run clean extra
    assert_status "$ZIGM_EX_USAGE" zigm_run which zig extra
}

test_argument_count_is_checked_before_dependencies() {
    # install checks its arguments first, so a machine without curl or jq still
    # gets the usage error rather than a missing tool error.
    assert_status "$ZIGM_EX_USAGE" zigm_run install
}

test_double_dash_ends_the_options() {
    assert_status 0 zigm_run -- list
    assert_status "$ZIGM_EX_USAGE" zigm_run -- --help
}

test_verbose_prints_debug_output() {
    zigm_out=$(zigm_run_out -v list)
    assert_contains "$zigm_out" 'zigm: debug: platform:' 'platform debug line'
    assert_contains "$zigm_out" 'zigm: debug: data dir:' 'data dir debug line'
}

test_quiet_and_verbose_are_accepted() {
    assert_status 0 zigm_run -q list
    assert_status 0 zigm_run --quiet --verbose list
}

test_quiet_silences_the_asides() {
    assert_eq '' "$(zigm_run_out -q list)" 'quiet output'
}

test_debug_output_is_off_by_default() {
    assert_eq '' "$(zigm_run_out list | grep 'zigm: debug:')" 'debug output'
}

test_use_creates_the_data_directories() {
    zigm_run use 0.15.1 >/dev/null 2>&1
    assert_dir "$ZIGM_TMP/data/versions" 'versions dir'
    assert_dir "$ZIGM_TMP/cache" 'cache dir'
}

test_sourcing_with_zigm_lib_runs_nothing() {
    # shellcheck disable=SC2016,SC2086 # the -c body expands in the child, and
    # ZIGM_SHELL_CMD may carry options.
    zigm_out=$(ZIGM_LIB=1 $ZIGM_SHELL_CMD -c \
        '. "$1"; printf "%s\n" "$ZIGM_VERSION"' _ "$ZIGM_BIN" 2>&1)
    assert_eq "$ZIGM_VERSION" "$zigm_out" 'sourced output'
}

test_sourcing_with_zigm_lib_ignores_arguments() {
    # shellcheck disable=SC2086 # ZIGM_SHELL_CMD may carry options.
    assert_status 0 env ZIGM_LIB=1 $ZIGM_SHELL_CMD "$ZIGM_BIN" frobnicate
}

run_tests
