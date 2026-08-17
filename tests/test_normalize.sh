#!/bin/sh
#
# Tests for the platform name normalizers.

# shellcheck source-path=SCRIPTDIR
. "$(dirname -- "$0")/lib.sh"

test_normalize_os_known() {
    assert_out linux normalize_os Linux
    assert_out macos normalize_os Darwin
    assert_out freebsd normalize_os FreeBSD
    assert_out netbsd normalize_os NetBSD
    assert_out openbsd normalize_os OpenBSD
    assert_out dragonfly normalize_os DragonFly
}

test_normalize_os_unknown_is_lowercased() {
    assert_out sunos normalize_os SunOS
    assert_out 'mingw64_nt-10.0' normalize_os 'MINGW64_NT-10.0'
}

test_normalize_os_of_uname_is_not_empty() {
    assert_ne '' "$(normalize_os "$(uname -s)")" 'host os'
}

test_normalize_arch_known() {
    assert_out x86_64 normalize_arch x86_64
    assert_out x86_64 normalize_arch amd64
    assert_out aarch64 normalize_arch aarch64
    assert_out aarch64 normalize_arch arm64
    assert_out armv7a normalize_arch armv7
    assert_out armv7a normalize_arch armv7l
    assert_out riscv64 normalize_arch riscv64
    assert_out powerpc64le normalize_arch ppc64le
}

test_normalize_arch_x86_variants() {
    assert_out x86 normalize_arch i386
    assert_out x86 normalize_arch i486
    assert_out x86 normalize_arch i586
    assert_out x86 normalize_arch i686
}

test_normalize_arch_unknown_passes_through() {
    assert_out s390x normalize_arch s390x
}

test_require_platform_sets_globals() {
    require_platform
    assert_ne '' "$ZIGM_OS" 'ZIGM_OS'
    assert_ne '' "$ZIGM_ARCH" 'ZIGM_ARCH'
}

run_tests
