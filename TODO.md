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
        - [X] `tests/test_install.sh` covers install and update, over real
              tarballs built at test time and a stubbed downloader.
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
- [X] Implement `install`.
    - [X] Add the `--no-zls` flag, which is what makes an install without a
          paired zls succeed rather than fail.
        - Nothing is asked of the version selection API in that case, since the
          answer would only be thrown away.
    - The layout the local commands assume is `versions/<version>/`, holding
      the zig and zls binaries beside zig's `lib` directory, since zig finds
      that directory relative to its own path.
    - A scratch directory used while unpacking must be dot prefixed, since
      `list` skips those and would otherwise report a half finished install.
    - [X] Settle what an install of a version that is already there does.
        - Settled: it says so and stops, and `--force` is how a reinstall is
          asked for.
    - [X] A finished install activates the version, with `--no-use` to skip
          that.
    - [X] Only the binary is taken out of the zls tarball, since it also ships
          a LICENSE and a README that would otherwise land on zig's.
    - [X] The tarballs are downloaded into the scratch directory and removed
          once unpacked, so the cache holds only the index and a failed install
          leaves nothing anywhere.
    - [X] Verify a download against the shasum upstream published for it.
        - A mismatch is fatal, while nothing to compare against, from a missing
          tool or a missing shasum, is a warning.
        - The tools disagree on where the digest sits in their output, so it is
          picked out by its shape rather than by its position.
    - [X] A reinstall moves the old version aside and puts it back when the
          swap fails, so a failure cannot lose a working install.
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
- [X] Implement `update`.
    - [X] It is an install of master that always refetches the index, and it
          takes `--no-zls` and `--force` for the same reasons install does.
    - [X] `current` follows the new nightly only when it pointed at a nightly
          already, or when nothing was active, so a pinned release is never
          moved out from under the user.
- [X] Drop exit code 3, since no subcommand is a stub any more.
- [X] Keep every recursive removal away from the root directory.
    - [X] `is_removable` refuses the root, however it is spelled, and `clean`
          asks it about the one directory a user names.
        - `pwd -P` may print the root as `//`, which it is free to do for
          exactly two leading slashes and which bash does.
        - `cd ''` is unspecified and succeeds under dash and zsh, so an empty
          path is refused before `cd` sees it.
    - [X] The paths built from a version name guard their parts with
          `${var:?}` instead, since a name that passed `is_version_name`
          already keeps them a component below the versions directory.
    - [X] The test for the refusal replaces `rm`, so a regression fails the
          test rather than the machine.
- [X] Implement `clean`.
    - The whole cache directory goes, since it holds only the download index
      and tarballs, both refetched on demand.
- [X] Replace the `dirname --` call in `fetch_cached`.
    - Busybox parses its own arguments per applet, so `--` may well be read as
      the path rather than as the end of the options.
    - `${path%/*}` does the same job with no external command, guarding the
      case of a path holding no slash, where it expands to the path itself.
- [ ] Keep `shellcheck -S style zigm` clean.
- [X] Write README covering install and the `PATH` setup the user must do.
    - Also covers the requirements, every command and flag, the on disk layout,
      and how to run the tests.
- [ ] Investigate whether `sed` alone can replace `jq`, dropping the last hard
      dependency.
    - [ ] Move config to a simpler to read and write format like `conf`.
- [ ] Version aliases, deferred.
- [ ] Config file, deferred.
- [ ] Minisign signature verification, deferred.
