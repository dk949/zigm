# TODO

- [X] Settle design decisions with the user (see CLAUDE.md).
- [X] Scaffold `zigm` with usage, arg parsing, and subcommand dispatch.
    - Global flags are `-h`, `-V`, `-v`, `-q`, and each subcommand is a stub
      that checks its argument count, declares the tools it needs, then exits 3.
    - Exit codes are 0 success, 1 error, 2 usage error, 3 not implemented.
    - Sourcing with `ZIGM_LIB=1` skips `main`, so a test harness can call
      single functions.
- [X] Detect platform and resolve data, cache, and config dirs.
    - [X] XDG on Linux and BSD.
    - [X] `~/Library/...` on Darwin.
    - [X] Env overrides `ZIGM_DATA_DIR`, `ZIGM_CACHE_DIR`, `ZIGM_CONFIG_DIR`,
          added for testing and for users who want a custom prefix.
- [X] Detect required tools and error clearly when one is missing.
    - [X] Downloader: `curl` or `wget`.
    - [X] Extraction: `tar` plus `xz`.
        - `xz` as a separate binary is preferred, since detecting xz support
          inside `tar` can only be done by grepping its help output.
    - [X] `jq`.
- [X] Detect a sha256 tool, warn loudly when none is available.
- [X] Set up a test harness that sources `zigm` with `ZIGM_LIB=1`.
    - [X] Keep new functions split into pure `find_*` and `normalize_*` helpers
          and `require_*` wrappers that set globals and exit on failure.
    - [X] `tests/run.sh` runs every `tests/test_*.sh` under the shells named in
          `SHELLS`, syntax checking `zigm` under each one first.
    - [X] `tests/lib.sh` sources `zigm`, defines the assertions, and runs each
          `test_*` function in its own subshell.
    - [X] Cover the normalizers, directory resolution, tool detection, and the
          command line end to end.
    - [ ] Extend the coverage as each remaining subcommand lands.
- [X] Run the tests, `shellcheck`, and a syntax check in CI.
    - [X] GitHub Actions, on push and pull request.
    - [X] Linux matrix of dash, bash, mksh, ksh, busybox ash, and zsh in sh
          emulation.
    - [X] macOS matrix of sh, bash, and zsh, since its directory layout
          differs.
    - [X] `shellcheck` pinned to a release, so a new version cannot turn a
          green branch red on its own.
- [ ] Resolve host arch and OS to a Zig release target triple.
- [ ] Resolve a zig version from the ziglang.org download index.
    - [ ] Tagged releases.
    - [ ] `master`, recording the concrete dev version.
- [ ] Resolve the matching zls build from the zigtools select-version API.
- [ ] Implement `install`.
- [ ] Implement `use` via an atomic `current` symlink swap.
- [ ] Implement `uninstall`.
- [ ] Implement `list` and `list-remote`.
- [ ] Implement `which` and `current`.
- [ ] Implement `update`.
- [ ] Implement `clean`.
- [ ] Keep `shellcheck -S style zigm` clean.
- [ ] Write README covering install and the `PATH` setup the user must do.
- [ ] Investigate whether `sed` alone can replace `jq`, dropping the last hard
      dependency.
    - [ ] Move config to a simpler to read and write format like `conf`.
- [ ] Version aliases, deferred.
- [ ] Config file, deferred.
- [ ] Minisign signature verification, deferred.
