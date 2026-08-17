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
        - [X] `tests/test_local.sh` covers the commands that only read local
              state, end to end over fake installs made of stub executables.
        - [X] `list-remote` is covered in `tests/test_resolve.sh`, since it
              reads the cached index the resolution tests already fixture.
- [X] Run the tests, `shellcheck`, and a syntax check in CI.
    - [X] GitHub Actions, on push and pull request.
    - [X] Linux matrix of dash, bash, mksh, ksh, busybox ash, and zsh in sh
          emulation.
    - [X] macOS matrix of sh, bash, and zsh, since its directory layout
          differs.
    - [X] `shellcheck` pinned to a release, so a new version cannot turn a
          green branch red on its own.
- [X] Resolve host arch and OS to a Zig release target key.
    - Both APIs key their per platform builds by `<arch>-<os>`, so there is no
      full triple to build.
    - [X] Try a short list of candidate keys, since zig renamed `armv7a` to
          `arm` in 0.15.1 and `i386` to `x86` in 0.11.0, while zls kept the
          old spellings.
- [X] Cache the download index in the cache directory.
    - [X] A stamp file beside it holds the download time, since there is no
          portable way to read a file's mtime.
    - [X] `ZIGM_INDEX_TTL` sets how long a copy stays fresh, one hour by
          default.
    - [X] `--refresh` ignores the cached copy, and `update` sets it, since
          `master` moves under it.
    - [X] A system whose `date` cannot print epoch seconds just refetches
          every time.
- [X] Resolve a zig version from the ziglang.org download index.
    - [X] Tagged releases, falling back to the requested version when the
          entry carries no `version` field, as releases before 0.15.1 do not.
    - [X] `master`, recording the concrete dev version.
    - [X] A missing shasum is tolerated, since checksum verification is a
          warning rather than an error.
- [X] Resolve the matching zls build from the zigtools select-version API.
    - [X] Percent encode the `+` in a dev version, which the API otherwise
          reads as a space and rejects with a 400.
    - [X] Report the API's own message when it has no pairing to offer, since
          it returns those as a json object with a 200.
- [X] Decide what `install` should do when no zls pairs with a zig version.
    - The API has a build for every tagged release, but a fresh nightly can
      resolve to an older zls or to nothing at all.
    - Settled: the install fails unless `--no-zls` was passed, in which case
      zig is installed alone and a warning says zls was skipped.
- [ ] Implement `install`.
    - [ ] Add the `--no-zls` flag, which is what makes an install without a
          paired zls succeed rather than fail.
    - The layout the local commands assume is `versions/<version>/`, holding
      the zig and zls binaries beside zig's `lib` directory, since zig finds
      that directory relative to its own path.
    - A scratch directory used while unpacking must be dot prefixed, since
      `list` skips those and would otherwise report a half finished install.
- [X] Implement `use` via an atomic `current` symlink swap.
    - [X] The swap goes through a scratch symlink beside `current`.
    - [X] `mv` moves the scratch link inside the old target unless told not
          to, and the option saying so is `-T` on GNU and `-h` on BSD, so both
          are tried before falling back to an unlink and a rename.
    - [X] The fallback loses atomicity, so the swap ends by checking where the
          link points, which also catches an `mv` that ignored both options.
    - [X] `use master` explains that a nightly is stored under the version it
          resolved to.
- [X] Implement `uninstall`.
    - [X] Removing the active version drops the `current` link first and
          warns, so nothing is left pointing into a half deleted directory.
- [X] Implement `list`.
    - [X] Versions sort oldest first, with a `-dev` build ahead of the release
          it leads up to.
    - [X] The active version is starred, and an empty list says so on stderr.
- [X] Implement `list-remote`.
    - [X] Only versions the index carries a build of for this platform are
          listed, since the rest cannot be installed here anyway.
    - [X] `master` is listed under the version it resolves to today, annotated
          with `(master)`, which is the name it would be installed under.
    - [X] The order matches `list`, oldest first, and the active version keeps
          its star, with an `i` on one that is installed but not active.
- [X] Implement `which` and `current`.
    - [X] `which` prints the path under `versions`, not the one through
          `current`, since that names the version the binary belongs to.
- [ ] Implement `update`.
- [X] Implement `clean`.
    - The whole cache directory goes, since it holds only the download index
      and tarballs, both refetched on demand.
- [X] Replace the `dirname --` call in `fetch_cached`.
    - Busybox parses its own arguments per applet, so `--` may well be read as
      the path rather than as the end of the options.
    - `${path%/*}` does the same job with no external command, guarding the
      case of a path holding no slash, where it expands to the path itself.
- [ ] Keep `shellcheck -S style zigm` clean.
- [ ] Write README covering install and the `PATH` setup the user must do.
- [ ] Investigate whether `sed` alone can replace `jq`, dropping the last hard
      dependency.
    - [ ] Move config to a simpler to read and write format like `conf`.
- [ ] Version aliases, deferred.
- [ ] Config file, deferred.
- [ ] Minisign signature verification, deferred.
