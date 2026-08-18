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
        - Removed again once the parser below replaced it.
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
        - [X] `tests/test_env.sh` covers `env`, over a zig stub printing a
              fixture in each of the two shapes.
        - [X] `tests/test_query.sh` covers the version queries, the two
              wrappers over them, and `use` and `uninstall` end to end.
        - [X] `tests/test_config.sh` covers the config file reader, the
              precedence against the environment, and a whole run reading a
              file.
        - [X] `tests/test_previous.sh` covers the record of the replaced
              version and the wrapper that writes it, over empty directories
              and a symlink rather than over installs.
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
- [X] Investigate whether `sed` alone can replace `jq`, dropping the last hard
      dependency.
    - Settled: `awk` rather than `sed`, since a parser needs to hold a token
      stream and `sed` would only work by leaning on the layout upstream
      happens to print today.
    - [X] `json_flatten` reads a document on stdin and prints one line per
          scalar: the path to it in tab separated fields, then its value in the
          last field, which grep and awk read directly.
        - Tokens never span lines, since json forbids a raw newline inside a
          string, so each line is tokenized on its own and the tokens are
          parsed as one stream in the END action.
        - An empty object or array prints its path with an empty value, so a
          lookup can still tell that the key is there, which is the whole of
          what `find_target` asks.
        - Only `\"`, `\\`, and `\/` are turned back into the character they
          stand for, which keeps a tab or a newline out of a value and so out
          of the line format. The rest is passed through as written, since
          these documents hold urls, digests, dates, and version strings.
    - [X] `json_has`, `json_field`, and `json_subfield` are the three lookups
          the rest of the script makes over that form.
    - [X] `find_release` and `find_remote_versions` flatten the index, and
          everything downstream of them takes the flattened form rather than
          json.
        - `find_remote_versions` reads an entry as an object when its paths run
          deeper than the entry itself, which is what `jq`'s type test did.
    - [X] Checked against the real download index, where the output matches
          `jq` line for line, and under `gawk` in both its posix and its
          traditional mode.
        - The ubuntu runners use mawk and the macos ones the one true awk, so
          CI covers the two implementations that are not gawk.
    - [X] `tests/test_json.sh` covers the parser and the three lookups, and the
          resolution tests now flatten their json fixtures before feeding them
          to a lookup.
    - [X] Drop `require_jq`, and with it the only thing `install`, `update`,
          and `list-remote` checked for that a POSIX system would not already
          have.
- [ ] User defined version aliases, unblocked now the config file has landed.
    - The built in half landed as `latest` and `stable`, which
      `find_version_match` answers, so what is left is a name the user picks.
    - [ ] Settle where an alias is written, likely `alias.<name>` in the
          config file, whose first key set leaves it out but whose parser
          takes a dotted key already.
    - [ ] Settle whether an alias names a query or a concrete version, since
          one standing for `0.15` moves as `0.15.x` grows.
    - [ ] Settle what an alias shadowing a built in name or a version name
          does, likely refusing the alias rather than the version.
- [X] Config file.
    - Nothing blocks it, and three landed items already want it: the three
      download knobs, the index TTL, and a mirror preference later.
    - [X] Settle the name and the location.
        - Settled: `<config>/zigm.conf`, one fixed path, since
          `ZIGM_CONFIG_DIR` already redirects it for a custom prefix and for a
          test, so neither a `--config` flag nor a second env var is wanted.
    - [X] Settle the format.
        - Settled: flat `key = value` lines, `#` comments, surrounding space
          ignored, and a dot grouping related keys, as in `alias.work`, so
          nothing has to carry a section while reading.
    - [X] Settle the key set.
        - Settled: the four knobs that are env only today, `connect_timeout`,
          `retries`, `retry_delay`, and `index_ttl`.
        - Aliases, the directories, and per command flag defaults are all left
          out of the first version, though the dotted names above are the
          shape an alias would take.
    - [X] Settle the precedence.
        - Settled: a flag over the environment over the file over the built in
          default, so the file holds a default a single run can still override
          without editing it.
        - The defaults are assigned as the script loads, so a value the file
          carries cannot be told from one the environment set until that
          assignment moves below the read.
    - [X] Settle when it is read.
        - Settled: once in `main`, after `require_dirs`, whatever the command,
          so every command sees the same values and one place reports a
          failure.
    - [X] Settle what a key the script does not know does.
        - Settled: a warning and a carry on, so an older zigm reads a file
          written for a newer one, and `-q` drops the warning like any other.
    - [X] Settle what a line the parser cannot read, or a value of the wrong
          shape, does.
        - Settled: it fails the command, the way `normalize_env` refuses a
          line it cannot read, since either one is a mistake rather than a
          difference between versions.
    - [X] Settle whether the effective values can be inspected.
        - Settled: no subcommand for now, and `-v` names the file that was
          read, which is also how a user checks it was found at all.
    - [X] Parse it rather than sourcing it, since sourcing hands a config file
          the whole shell.
        - `normalize_config` is an awk pass printing the tab separated shape
          `json_flatten` prints, and `config_field` reads it in the style of
          `json_field`.
    - [X] Read and check it in one pass, since an unknown key warns and a bad
          line fails, and neither is known without looking at the whole file.
        - [X] Settle how the values reach the globals, since sourcing is out
              and a lookup per key is one pass over the file per key.
            - Settled: the file is parsed once into `ZIGM_CONFIG_TEXT`, and
              every lookup after that reads that variable rather than the
              file, so the four knobs cost one pass in all.
        - The parse prints nothing until the last line has been read, so a
          file with a bad line in it prints that line's number in place of the
          settings and no half read file reaches a caller.
    - [X] Move the four defaults below the read, since they are assigned as
          the script loads and the file has to sit between the environment and
          them.
        - Each one stays unset until the environment, then the file, then the
          built in value has been tried, which is also what tells a value the
          file carried from one the environment set.
        - `config_settle` is what tries the three in that order, and
          `tests/lib.sh` calls it once, since a test that calls a single
          function never reads a config file.
    - [X] Map the two spellings in one place, since the environment says
          `ZIGM_RETRIES` and the file says `retries`.
        - `config_settle` holds the four pairs, one line each, beside the
          default that pair falls back to.
    - [X] Check each value's shape as it is read, since a value of the wrong
          shape fails the command, and the four are all non negative integers.
        - The check is on the file's value alone, since the environment has
          never been checked and doing so now would refuse a value an older
          zigm took.
    - [X] `-v` names the file that was read, and says so when there is none,
          and names each value it settled beside where that value came from.
    - [X] `usage` and the README gain the file, its location, its keys, and
          the precedence, beside the environment list they carry today.
    - [X] `tests/test_config.sh` covers the reader, the precedence against the
          environment, an unknown key, a bad line, and a bad value, with one
          end to end run whose file changes a knob.
        - A test names its own config directory already, so the file lands in
          scratch space like everything else.
    - The settled note that `-q` drops the unknown key warning was not
      followed: `warn` is loud whatever the verbosity, and `usage` says `-q`
      prints errors and warnings only, so this one warns like every other.
- [ ] `-v` prints the whole settled configuration for a run.
    - `config_knob` names a value only when the environment or the file gave
      it one, so a run with no config file says nothing about any of the four
      and a user checking what a run used has to know that silence means the
      built in default.
    - [ ] Settle whether a value that fell back names its source, likely
          saying so in the same words the other two use, since the point is
          that every value is accounted for.
    - [ ] Settle whether the lines stay where they are, one per value as it is
          settled, or become one block printed after the read, which would
          keep the four together whatever order they were settled in.
    - [ ] Keep it growing with the key set, since a value added later that is
          not printed puts the gap back.
    - [ ] `tests/test_config.sh` covers a run with no config file naming all
          four values.
- [ ] Minisign signature verification, deferred.
- [X] `env` sub-command to unify the environment output of `zig env`
    - Prints output of current `zig env` in JSON
    - This was moved from JSON to ZON in zig 0.15
    - [X] Settle what it prints, since one of the two shapes has to win.
        - Settled: always json, so a caller reads one format whichever version
          is active.
    - [X] `normalize_env` takes what zig printed and prints json, passing a
          json document through and converting a zon one.
        - The zon zig writes here is a struct of strings, nulls, and nested
          structs, one field to a line, so an awk over the lines is enough and
          no zon parser is needed.
        - A line it cannot read fails the whole command rather than being
          guessed at, since half a document is worse than none.
        - Commas move from the end of every field in zon to between the
          members in json, so the converter holds one line back and decides
          its comma once it has seen the line after it.
        - An escape zig has and json does not, `\xNN`, is passed through as it
          stands, since the values here are paths and version strings.
    - [X] `cmd_env` runs the active version's zig, like `which` it resolves
          through `versions` rather than through `current`.
        - It takes no lock and needs no network, since it only reads.
- [ ] Follow upstream's download policy, which points tooling at the community
      mirrors rather than at ziglang.org.
    - [ ] Check what the policy asks for today, since the mirror list is its
          own file and `index.json` is of uncertain lifetime.
    - A mirror is not trusted, so this waits on minisign verification, which
      is what makes installing from one safe.
    - A config file is likely wanted too, for a user who prefers one mirror or
      wants ziglang.org back.
- [X] Test the command lines the downloaders are called with.
    - `tests/test_install.sh` replaces `fetch_file` and `fetch_stdout`, so no
      test sees the flags either downloader is given.
    - [X] `tests/test_fetch.sh` defines `curl` and `wget` as functions that
          record their arguments, which covers both.
        - A stub runs inside a command substitution, so one counting its calls
          counts them in a file rather than in a variable, which would not
          survive the subshell.
    - Busybox parses its options per applet, so the `--` these pass is the
      shape that had to come out of `fetch_cached`'s `dirname` call.
- [X] Give both downloaders a connect timeout and a retry count.
    - A hung mirror otherwise hangs an install with no output and no way out
      of it but a kill.
    - [X] Settle where the retry lives, since busybox wget has `-T` but no
          `-t` and refuses the whole download when given one.
        - Settled: the timeout is the downloader's, `--connect-timeout` on
          curl and `-T` on wget, and the retry is a loop in `fetch_retry`,
          which is the same on either tool and on either wget.
    - [X] GNU wget retries 20 times on its own, which multiplies that loop, so
          it is told `-t 1` when its help names the option.
    - [X] `ZIGM_CONNECT_TIMEOUT`, `ZIGM_RETRIES`, and `ZIGM_RETRY_DELAY` set
          the three numbers, and a config file would be where a user changes
          them once there is one.
    - [X] A body bound for stdout is held back until the downloader is done
          with it, so a transfer cut off halfway is dropped rather than mixed
          with the retry that follows.
- [X] Say why a download failed, not only that it did.
    - `curl -fsS` and `wget -q` swallow the reason, so a 404, a DNS failure,
      and a TLS failure all reach the user as `cannot download <url>`.
    - [X] Neither downloader is asked to be quiet about a failure any more,
          and `fetch_retry` captures their stderr rather than showing it, so
          an attempt that is tried again says nothing.
        - The capture keeps the body and the diagnostics apart by putting the
          body on fd 3, opened on a group around the assignment rather than on
          the assignment itself, since a shell is free to expand the one
          before it applies the redirection, and bash does.
    - [X] The terminal gets the last two lines the downloader wrote, above
          zigm's own message, and everything it wrote under `-v`.
        - curl says the whole of it in one line, while wget puts the reason in
          the line before its last, which is often no more than `Giving up.`.
    - The log file below is still where the rest of the detail should go.
- [ ] Write a log file, holding the detail the terminal does not carry.
    - [X] Settle where it lives.
        - Settled: a state directory, a fourth kind beside data, cache, and
          config, `XDG_STATE_HOME/zigm` on Linux and BSD and
          `~/Library/Application Support/zigm` on Darwin, which is where its
          state already goes.
        - The log is `<state>/log`, and the `use -` record below is
          `<state>/previous`, so the state directory serves both.
        - `base_dir` gains the kind, `require_dirs` the global, and
          `ZIGM_STATE_DIR` overrides it the way the other three are overridden.
        - All three landed with the `use -` item below, which wanted the same
          directory, so what is left here is the log itself.
    - [X] Settle whether it is one file or one per run, and how much is kept.
        - Settled: one file every run appends to, and a run that finds it over
          a size cap keeps the tail and drops the rest, so nothing has to
          sweep it and it never grows without bound.
        - [ ] Settle the cap, and whether a key sets it, which the config file
              settled above leaves out of its first key set.
    - [X] Settle what is written to it.
        - Settled: everything `-v` prints, whatever the verbosity of the run,
          the downloader output the terminal shows two lines of, and a line at
          each end of the run naming the command line and the exit status.
    - [X] Settle whether it is written by default.
        - Settled: yes, since a failure is only reported out of a log that was
          already being written, and the cap bounds what that costs.
    - [X] Settle how a line is stamped.
        - Settled: once per run, in the run line, which carries the pid and
          `date '+%Y-%m-%d %H:%M:%S'`, whose conversion specs are POSIX where
          `%s` is not.
        - Everything below that line is unstamped, so an appended block costs
          nothing per line and one `date` covers the run.
    - [X] Settle what a log that cannot be written does.
        - Settled: one warning, dropped by `-q`, and the command carries on,
          since no work depends on the log, but a state directory that cannot
          be written is worth saying once.
    - [X] Settle whether two runs may write at once.
        - Settled: every write is an append and every line carries the pid, so
          two runs are told apart rather than kept apart, which the read only
          commands need since they take no lock.
        - The trim is the racy part, and only a run that finds the file over
          the cap does it.
    - [X] Settle whether `clean` removes it.
        - Settled: no, `clean` keeps to the cache and the install scratch,
          both rebuilt on demand, while the cap is what bounds the log and a
          log is the one thing a user still wants after a failure.
- [X] Accept a partial version, resolving `0.15` to the newest `0.15.x`.
    - [X] Build it as the version query mechanism the deferred aliases reuse,
          since both turn what the user typed into a concrete version.
        - `find_version_match` answers a query against a list of versions, and
          the two `require_*` wrappers over it name the list: the installed
          versions for `use` and `uninstall`, the index for `install`.
        - `is_exact_version` is what keeps a concrete version out of all of
          that, so it costs no index fetch and fails in the words it did
          before.
    - [X] Add `latest` and `stable` as built in aliases, the one naming
          `master`, which already covers it, and the other the newest tagged
          release.
    - [X] Settle which commands take a query.
        - Settled: `install` and `update` answer one against the index, `use`
          and `uninstall` against what is installed, and no other command
          names a version.
    - [X] Settle whether a partial version may answer with a nightly.
        - Settled: no, a tagged release alone, since a nightly moves under the
          release it leads up to and the answer would depend on the day.
        - An exact name still reaches a nightly, so one is nameable in full.
        - `use latest` is therefore `use master`, which says that a nightly is
          stored under the version it resolved to.
    - [X] A name the list carries wins over the newest match, so a version
          whose name is a prefix of another resolves to itself.
- [ ] Keep the nightlies from piling up, deferred.
    - `master` re-resolves on every install, so each one leaves the last
      nightly behind and only an explicit uninstall removes it.
    - [ ] Settle the shape, likely `zigm keep <version>` to pin one and
          `zigm prune` to drop the rest.
- [ ] Run one command under a version without activating it.
    - `zigm which` already prints the path to run, so what this adds is not
      having to spell that path out.
    - [ ] Settle whether it earns a subcommand at all, since a shell function
          over `which` covers most of it.
    - [ ] Settle the name, `run` or `exec`, and the shape, likely
          `zigm run <version> <command> [args...]`.
    - [ ] Settle how the version reaches the command, since putting its
          directory on `PATH` also covers a zig the command runs itself, while
          resolving the command under it does not.
    - [ ] Settle what an argument shaped like a zigm flag does, since
          everything past the command name belongs to the command.
    - [ ] Settle what an uninstalled version does, likely failing rather than
          installing it.
    - It takes no lock and needs no network, since it only reads, and a query
      resolves against the installed versions the way `use` does.
- [X] Warn when the `current` directory is not on `PATH`, as the last step of
      an install.
    - It is the one piece of setup zigm leaves to the user, so it is the most
      likely thing to be missing.
    - [X] Settle which commands check.
        - Settled: every command that activates a version, so `install`,
          `update`, and `use` all report the same thing.
    - [X] Settle how strict the check is.
        - Settled: the link has to be on `PATH` and the zig `PATH` leads to has
          to be the one under it, so a system zig ahead of the link is reported
          too.
    - [X] `is_on_path` compares physical paths, so a symlinked home, a trailing
          slash, and a `..` on the way all still match.
        - `find_real_dir` is the resolution the rest of the script already made
          inline, now named, and the three callers it had take it too.
        - An entry is a path rather than a pattern, so globbing is off for the
          split.
    - [X] `find_zig_dir` walks the same list rather than asking `command -v`,
          which answers for the path this run was started with rather than for
          the one it is asked about.
    - [X] `warn_path` says which of the two is wrong, and follows it with the
          line that fixes it, as a `note` rather than a warning so `-q` drops
          it while the warning stands.
    - [X] `tests/test_path.sh` covers the three functions and `use` end to end.
        - A test naming a path list keeps the real one on the end, since mksh
          reaches `printf` through it.
- [X] Add an alias `-`, when used as `zigm use -`, reverts back to the previous
      used version.
    - [X] Settle where the previous version is recorded.
        - Settled: `<state>/previous`, in the state directory the log file
          item settled above, since the `.zigm` meta is per version and this
          record belongs to neither a version nor the cache.
        - The state directory landed here rather than with the log file:
          `base_dir` took the kind, `require_dirs` the `ZIGM_STATE_DIR` and
          `ZIGM_PREVIOUS_FILE` globals, and `ensure_dirs` creates it.
    - [X] Settle who writes it.
        - Settled: `activate_version`, a wrapper over `swap_link` that reads
          the link, swaps it, and records what was there, which `cmd_use` and
          `install_version` both go through so `use`, `install`, and `update`
          all record alike.
        - `swap_link` stays a link primitive, so nothing about the record can
          leak into the one caller that only wants a symlink moved.
    - [X] Settle what an activation that changes nothing does.
        - Settled: it leaves the record alone, so a `use` of the version that
          is active already does not cost the user their way back, and a first
          activation, with nothing active before it, records nothing.
    - [X] Settle what two `use -` runs in a row do.
        - Settled: they swap back and forth, which falls out of every
          activation recording what it replaced.
    - [X] Settle what a record naming an uninstalled version does, and what a
          missing record does.
        - Settled: an error naming which of the two it is, and the record is
          left as it stands either way, so a version installed again is still
          reachable through it.
    - [X] Keep `-` out of `find_version_match`, since `use` resolves it to a
          version first, the way a concrete name never reaches a query.
    - [X] `tests/test_previous.sh` covers the three new functions, and
          `tests/test_local.sh` covers `use -` end to end, including the two
          errors and the activation that records nothing.
