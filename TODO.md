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
- [X] Accept the global flags after the subcommand as well as before it.
    - `zigm install -v 0.15.1` and `zigm list-remote --refresh` were both a
      usage error, since only the leading flags were parsed.
    - [X] `main` walks the whole line, shifting each argument off the front and
          either consuming it or appending it back, since an argument list is
          the only list POSIX sh has.
        - A counter of the arguments still to look at keeps an appended one
          from being read a second time.
        - An unknown option before the command stays zigm's own to refuse,
          while one after it is passed on for the command to refuse.
        - Everything past a `--` is the command and its arguments, whatever it
          looks like.
    - [X] Give each subcommand a `--help` of its own, which was an unknown
          option.
        - `usage_command` holds one help text per command, and `main` prints it
          for a `--help` found anywhere on a line naming a command, so
          `zigm -h install` and `zigm install -h` agree.
        - The help is printed before any work, so it needs no active version
          and no network.
- [X] Sweep the install scratch directories left behind by a failed install.
    - `install_payload` writes `versions/.new-<version>` and
      `versions/.old-<version>`, and only an install of that same version
      clears them again, so an interrupt leaves them there for good.
    - [X] Decide between sweeping them in `clean`, which removes the cache
          alone today, and clearing them with a trap as the install exits.
        - Settled: both, since a trap cannot catch a kill, a crash, or a power
          loss, and `clean` cannot help an install that is still running.
    - [X] `reclaim_scratch` clears one version's pair and is the whole of the
          recovery, called from the trap, from the end of a finished install,
          and from `clean`.
        - Between the two renames `install_payload` makes, the old version is
          reachable only through `.old-`, so that one is put back rather than
          removed.
        - The restore `install_payload` did inline when the second rename
          failed is gone, since the trap now does it on the way out.
    - [X] The signal handlers only `exit`, leaving the work to the EXIT
          handler, which POSIX runs on the way out of an `exit` from a trap.
        - Checked by hand under sh, dash, bash, and zsh in sh emulation, since
          a test cannot signal the subshell it runs its subject in.
    - [X] `clean` sweeps every pair under the versions directory, before the
          cache removal, which returns early when the cache is already empty.
        - It is not behind a flag, since neither half of a pair is an install
          and both are rebuilt on demand.
- [X] Record which zls version an installed version holds.
    - Nothing on disk names it, so `list` and `current` cannot show it and an
      install made with `--no-zls` can only gain a zls through `--force`.
    - [X] Settle where it lives, since a file under the version directory sits
          beside the tarball's own contents.
        - Settled: a dot prefixed `.zigm` inside the version directory, holding
          `key=value` lines, of which `zls` is the only one so far.
        - It cannot collide with the tarball's own contents, and every rename
          that moves a version moves it too.
        - `install_payload` writes it into the scratch root, so it arrives with
          the rest of the install rather than in a step of its own.
    - [X] `list` and `current` show the zls in a column of their own, which
          they line up with each other.
        - A version whose record is missing reads `zls (unknown)`, since
          neither tarball names the version and an install made by an earlier
          zigm left nothing to read.
        - One holding no zls at all reads `no zls`.
        - A caller after bare names now takes the first field rather than the
          whole line.
    - [X] A plain install of a version holding no zls adds the zls it pairs
          with, so `--no-zls` can be filled in later without `--force`.
        - `install_zls_into` unpacks the binary in the same scratch directory
          an install works in and moves it in on its own, leaving the rest of
          the version alone, so a failure anywhere leaves it as it was.
- [X] Check whether a version is installed before resolving its zls.
    - `install_version` resolved the pairing first, so reinstalling an
      installed version asked the API for an answer it threw away, and failed
      outright when the pairing had since disappeared rather than saying the
      version is already installed.
    - [X] The pairing is resolved in the branch that assembles the install, so
          a version that is already there reaches the `current` swap without
          any network at all.
    - [X] The `--no-zls` warning moved along with it, since it announces a
          skipped resolution and has nothing to say about an installed
          version.
- [X] Decide whether concurrent installs need a lock.
    - Two installs of one version share `.new-<version>`, and the second
      removes what the first is assembling.
    - A `clean` run alongside an install sweeps the scratch out from under it,
      which the same lock would cover.
    - [X] Settled: one lock over the whole data directory, taken by every
          command that writes, and a second run exits rather than waiting.
        - A lock per version would not cover `clean`, which sweeps every
          version's scratch and would have to hold all of them.
        - `install`, `update`, `use`, `uninstall`, and `clean` take it, while
          `list`, `list-remote`, `which`, and `current` take nothing.
    - [X] The lock is the directory `<data>/.lock`, since `mkdir` is the only
          exclusive create POSIX sh has, and it holds the pid of the run that
          took it.
        - A lock whose owner is gone is reclaimed, since a kill or a power loss
          leaves nobody to give it back.
        - `kill -0` cannot see another user's process, but a data directory
          belongs to one user, so a live owner is always one of their own.
        - A lock recording no pid is not reclaimed: a run that has not written
          its pid yet cannot be told from one that died in that window, one
          `printf` wide, so the message names the directory to remove.
    - [X] `require_lock` is re-entrant, since the lock is given back on the way
          out and a run taking it twice would otherwise report itself.
    - [X] One EXIT handler, `on_exit`, gives back both the lock and the scratch
          of a running install, since a shell keeps a single one and the traps
          `install_payload` set would otherwise clear it.
        - `ZIGM_SCRATCH_VERSION` names the version being assembled, replacing
          the trap that install set and cleared around its own work.
        - Checked by hand under sh, dash, bash, and zsh in sh emulation, which
          all give back both on a TERM and on a HUP, since a test cannot signal
          the subject it runs.
        - INT was not checked the same way, since a shell ignores it in a job
          it backgrounded, and it shares its handler with the other two.
- [ ] Investigate whether `sed` alone can replace `jq`, dropping the last hard
      dependency.
    - [ ] Move config to a simpler to read and write format like `conf`.
- [ ] Version aliases, deferred.
- [ ] Config file, deferred.
- [ ] Minisign signature verification, deferred.
- [ ] `env` sub-command to unify the environment output of `zig env`
    - Prints output of current `zig env` in JSON
    - This was moved from JSON to ZON in zig 0.15
