#!/bin/sh
#
# Tests for `env`, which prints the active zig's `zig env` as json whichever
# of the two shapes that zig wrote it in. Nothing here touches the network:
# the zig being asked is a stub printing a fixture.

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# What zig prints from 0.15 on.
zigm_zon=$(
    cat <<'EOF'
.{
    .zig_exe = "/opt/zig/zig",
    .version = "0.15.1",
    .env = .{
        .ZIG_LIB_DIR = null,
        .HOME = "/home/u",
    },
}
EOF
)

# What zig printed up to 0.14, which is already json.
zigm_json=$(
    cat <<'EOF'
{
 "zig_exe": "/opt/zig/zig",
 "version": "0.14.1",
 "env": {
  "ZIG_LIB_DIR": null,
  "HOME": "/home/u"
 }
}
EOF
)

# The json the zon above converts to.
zigm_want=$(
    cat <<'EOF'
{
  "zig_exe": "/opt/zig/zig",
  "version": "0.15.1",
  "env": {
    "ZIG_LIB_DIR": null,
    "HOME": "/home/u"
  }
}
EOF
)

# install_stub_zig <version> <what its `zig env` prints>
#
# Creates an installed version whose zig answers `env` with a fixture, which
# is all `zigm env` asks of it.
install_stub_zig() {
    install_stub_zig_dir="$ZIGM_TMP/data/versions/$1"
    mkdir -p "$install_stub_zig_dir" || fail "cannot create $install_stub_zig_dir"

    printf '%s\n' "$2" >"$install_stub_zig_dir/env.out" ||
        fail 'cannot write the fixture'

    cat >"$install_stub_zig_dir/zig" <<'EOF'
#!/bin/sh
[ "${1:-}" = env ] || exit 2
cat "$(dirname -- "$0")/env.out"
EOF
    chmod +x "$install_stub_zig_dir/zig" || fail 'cannot make the stub executable'
}

# activate <version>
activate() {
    zigm_run use "$1" >/dev/null 2>&1 || fail "cannot activate $1"
}

# reset_data
reset_data() {
    rm -rf "$ZIGM_TMP/data" || fail "cannot clear $ZIGM_TMP/data"
}

# ---------------------------------------------------------------------------
# normalize_env
# ---------------------------------------------------------------------------

test_normalize_env_passes_json_through() {
    assert_out "$zigm_json" normalize_env "$zigm_json"
}

test_normalize_env_converts_zon() {
    assert_out "$zigm_want" normalize_env "$zigm_zon"
}

test_normalize_env_converts_a_flat_struct() {
    assert_out '{
  "version": "0.15.1"
}' normalize_env '.{
    .version = "0.15.1",
}'
}

test_normalize_env_converts_an_empty_struct() {
    assert_out '{
}' normalize_env '.{
}'
}

test_normalize_env_quotes_an_enum_literal() {
    assert_out '{
  "mode": "Debug"
}' normalize_env '.{
    .mode = .Debug,
}'
}

test_normalize_env_keeps_a_value_holding_a_comma() {
    assert_out '{
  "target": "x86_64-linux, gnu"
}' normalize_env '.{
    .target = "x86_64-linux, gnu",
}'
}

test_normalize_env_reads_a_document_without_trailing_commas() {
    assert_out "$zigm_want" normalize_env '.{
    .zig_exe = "/opt/zig/zig",
    .version = "0.15.1",
    .env = .{
        .ZIG_LIB_DIR = null,
        .HOME = "/home/u"
    }
}'
}

test_normalize_env_fails_on_empty_input() {
    assert_fails normalize_env ''
}

test_normalize_env_fails_on_a_shape_it_cannot_read() {
    assert_fails normalize_env 'zig: error: no such command'
}

test_normalize_env_fails_on_a_truncated_document() {
    assert_fails normalize_env '.{
    .zig_exe = "/opt/zig/zig",'
}

test_normalize_env_fails_on_a_line_it_cannot_read() {
    assert_fails normalize_env '.{
    "zig_exe" = "/opt/zig/zig",
}'
}

# ---------------------------------------------------------------------------
# env
# ---------------------------------------------------------------------------

test_env_prints_json_from_a_zon_zig() {
    reset_data
    install_stub_zig 0.15.1 "$zigm_zon"
    activate 0.15.1
    assert_out "$zigm_want" zigm_run env
}

test_env_prints_json_from_a_json_zig() {
    reset_data
    install_stub_zig 0.14.1 "$zigm_json"
    activate 0.14.1
    assert_out "$zigm_json" zigm_run env
}

test_env_fails_when_no_version_is_active() {
    reset_data
    install_stub_zig 0.15.1 "$zigm_zon"
    assert_status "$ZIGM_EX_ERROR" zigm_run env
    assert_contains "$(zigm_run_out env)" 'no version is active' 'message'
}

test_env_fails_when_zig_cannot_be_run() {
    reset_data
    install_stub_zig 0.15.1 "$zigm_zon"
    activate 0.15.1
    chmod -x "$ZIGM_TMP/data/versions/0.15.1/zig" || fail 'cannot unset the bit'
    assert_status "$ZIGM_EX_ERROR" zigm_run env
    assert_contains "$(zigm_run_out env)" "has no 'zig'" 'message'
}

test_env_fails_when_zig_env_fails() {
    reset_data
    install_stub_zig 0.15.1 "$zigm_zon"
    activate 0.15.1
    printf '#!/bin/sh\nexit 1\n' >"$ZIGM_TMP/data/versions/0.15.1/zig" ||
        fail 'cannot replace the stub'
    assert_status "$ZIGM_EX_ERROR" zigm_run env
    assert_contains "$(zigm_run_out env)" "'zig env' failed" 'message'
}

test_env_fails_on_output_it_cannot_read() {
    reset_data
    install_stub_zig 0.15.1 'zig: error: unknown command'
    activate 0.15.1
    assert_status "$ZIGM_EX_ERROR" zigm_run env
    assert_contains "$(zigm_run_out env)" 'cannot read the output' 'message'
}

test_env_takes_no_arguments() {
    reset_data
    install_stub_zig 0.15.1 "$zigm_zon"
    activate 0.15.1
    assert_status "$ZIGM_EX_USAGE" zigm_run env extra
}

test_env_has_a_help_of_its_own() {
    assert_contains "$(zigm_run_out env --help)" 'usage: zigm env' 'help'
}

run_tests
