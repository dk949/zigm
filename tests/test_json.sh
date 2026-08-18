#!/bin/sh
#
# Tests for the json parser, which replaced the jq dependency.
#
# `json_flatten` reads a document on stdin, so every test here pipes a literal
# into it. The expected output is written with a `%s` per field and an explicit
# tab between them, since a literal tab in the source would be invisible.

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

# Flattens a document given as an argument.
zigm_flatten() {
    printf '%s\n' "$1" | json_flatten
}

# zigm_line <field>...
#
# Prints one line of a flattened document, the fields separated by tabs.
zigm_line() {
    printf '%s' "$1"
    shift
    for zigm_line_field in "$@"; do
        printf '\t%s' "$zigm_line_field"
    done
    printf '\n'
}

# ---------------------------------------------------------------------------
# Flattening
# ---------------------------------------------------------------------------

test_flatten_reads_a_nested_object() {
    zigm_out=$(zigm_flatten \
        '{"master":{"version":"0.17.0","x86_64-linux":{"tarball":"u"}}}')
    zigm_want=$(
        zigm_line master version 0.17.0
        zigm_line master x86_64-linux tarball u
    )
    assert_eq "$zigm_want" "$zigm_out" 'flattened document'
}

test_flatten_ignores_the_layout() {
    zigm_want=$(zigm_line a b c)
    assert_eq "$zigm_want" "$(zigm_flatten '{"a":{"b":"c"}}')" 'minified'
    assert_eq "$zigm_want" "$(zigm_flatten '{
        "a" :
            {   "b"   :  "c"   }
    }')" 'spread over lines'
}

test_flatten_keeps_an_empty_container_visible() {
    # An empty value is what a lookup for the key itself matches on, which is
    # how find_target tells a platform that is there from one that is not.
    zigm_want=$(zigm_line arm-linux '')
    assert_eq "$zigm_want" "$(zigm_flatten '{"arm-linux":{}}')" 'empty object'
    assert_eq "$zigm_want" "$(zigm_flatten '{"arm-linux":[]}')" 'empty array'
}

test_flatten_numbers_the_members_of_an_array() {
    zigm_out=$(zigm_flatten '{"a":["x","y",{"b":"z"}]}')
    zigm_want=$(
        zigm_line a 0 x
        zigm_line a 1 y
        zigm_line a 2 b z
    )
    assert_eq "$zigm_want" "$zigm_out" 'array members'
}

test_flatten_prints_a_non_string_as_written() {
    zigm_out=$(zigm_flatten '{"code":3,"ok":true,"none":null,"f":-1.5e10}')
    zigm_want=$(
        zigm_line code 3
        zigm_line ok true
        zigm_line none null
        zigm_line f -1.5e10
    )
    assert_eq "$zigm_want" "$zigm_out" 'literals'
}

test_flatten_reads_the_escapes_json_and_the_shell_share() {
    zigm_out=$(zigm_flatten '{"a":"x\"y\\z\/w"}')
    assert_eq "$(zigm_line a 'x"y\z/w')" "$zigm_out" 'unescaped'
}

test_flatten_passes_the_other_escapes_through() {
    # A raw tab or newline in a value would break the line format, and none of
    # the fields read here ever carries one.
    zigm_out=$(zigm_flatten '{"a":"x\ty\nzé"}')
    assert_eq "$(zigm_line a 'x\ty\nzé')" "$zigm_out" 'passed through'
}

test_flatten_does_not_stop_at_an_escaped_quote() {
    zigm_out=$(zigm_flatten '{"a":"x\"}","b":"c"}')
    zigm_want=$(
        zigm_line a 'x"}'
        zigm_line b c
    )
    assert_eq "$zigm_want" "$zigm_out" 'a brace inside a string'
}

test_flatten_fails_on_a_document_it_cannot_read() {
    assert_fails zigm_flatten 'not json'
    assert_fails zigm_flatten '{"a":'
    assert_fails zigm_flatten '{"a":1'
    assert_fails zigm_flatten '{"a" 1}'
    assert_fails zigm_flatten '{a:1}'
    assert_fails zigm_flatten '{"a":1} {"b":2}'
    assert_fails zigm_flatten ''
}

test_flatten_accepts_an_empty_document() {
    assert_out '' zigm_flatten '{}'
}

# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------

test_json_has_finds_a_top_level_key() {
    zigm_flat=$(zigm_flatten '{"a":{},"b":"c","d":{"e":"f"}}')
    assert_ok json_has "$zigm_flat" a
    assert_ok json_has "$zigm_flat" b
    assert_ok json_has "$zigm_flat" d
    assert_fails json_has "$zigm_flat" e
    assert_fails json_has "$zigm_flat" ''
}

test_json_field_reads_a_top_level_scalar() {
    zigm_flat=$(zigm_flatten '{"version":"0.15.1","empty":"","o":{"a":"b"}}')
    assert_out 0.15.1 json_field "$zigm_flat" version

    # A key that is missing, holds a container, or holds an empty string all
    # count as absent.
    assert_fails json_field "$zigm_flat" missing
    assert_fails json_field "$zigm_flat" empty
    assert_fails json_field "$zigm_flat" o
}

test_json_subfield_reads_one_level_down() {
    zigm_flat=$(zigm_flatten \
        '{"x86_64-linux":{"tarball":"u","deep":{"a":"b"}}}')
    assert_out u json_subfield "$zigm_flat" x86_64-linux tarball
    assert_fails json_subfield "$zigm_flat" x86_64-linux shasum
    assert_fails json_subfield "$zigm_flat" x86_64-linux deep
    assert_fails json_subfield "$zigm_flat" aarch64-linux tarball
}

run_tests
