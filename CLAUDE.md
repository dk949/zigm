# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`zigm` is a Zig toolchain manager: a single POSIX shell script that fetches
matched `zig` and `zls` versions and exposes one of them on `PATH`.

The repo is new. As of this file, only `TODO.md` and this file exist. Working
state lives in `TODO.md`.

## Commands

* Lint, must be clean at `style` severity:
  * `shellcheck -S style zigm tests/*.sh`
* Syntax check without executing:
  * `sh -n zigm`
* Test:
  * `tests/run.sh`, runs the whole suite under `sh`
  * `SHELLS='dash bash mksh ksh busybox zsh' tests/run.sh`, runs it under each
    named shell, syntax checking `zigm` under that shell first
  * `tests/run.sh tests/test_dirs.sh`, runs one file
* There is no build step.

## Design decisions

These were settled with the user. Do not silently revise them.

* One file, POSIX `sh`, no bashisms. Target any remotely POSIX shaped system.
* Required external tools, hard error if missing:
  * `curl` or `wget`, detected at runtime
  * `tar` with `xz` support, or `tar` plus a separate `xz`
  * Typical POSIX utilities: `awk`, `grep`, `sed`, and similar
* The json both upstream endpoints answer in is read by an `awk` parser in the
  script, `json_flatten`, which prints one line per scalar: the path to it in
  tab separated fields, then its value in the last field. There is no json tool
  dependency.
* Checksum verification uses whichever of `sha256sum`, `shasum`, `openssl`, or
  `cksum -a` is present. If none is found, emit a loud warning and continue.
* Signature verification (minisign) is deferred, not rejected.
* Activation is a single directory symlink, no shell integration:
  * `<data>/zigm/current -> <data>/zigm/versions/<version>/`
  * The user puts that `current` path on `PATH` themselves.
  * Switching versions is one atomic symlink swap.
* Version coverage is tagged releases plus `master` nightly.
  * `master` resolves to a concrete version at install time and is stored under
    its real version string, for example `0.16.0-dev.123+abc`.
  * `master` is a pointer that re-resolves on each install, so old nightlies
    persist until explicitly uninstalled.
* `zls` comes from the zigtools version selection API, which handles zig/zls
  pairing for both tagged and master:
  * `https://releases.zigtools.org/v1/zls/select-version?zig_version=<v>&compatibility=only-runtime`
* Directories are platform native:
  * Linux and BSD: XDG, honoring `XDG_DATA_HOME`, `XDG_CACHE_HOME`,
    `XDG_CONFIG_HOME`
  * Darwin: `~/Library/Application Support/zigm`, `~/Library/Caches/zigm`
* Subcommands for v1: `install`, `use`, `uninstall`, `list`, `list-remote`,
  `which`, `current`, `update`, `clean`.
* Deferred: version aliases and a config file. A config format simpler than
  json is preferred, since nothing else needs a json writer.

## Working rules

### General

* Keep responses as short as possible without losing information. Use
  abbreviations generously.
* If anything is even a little ambiguous or unclear, ask.
* Ask using the user survey tool (`AskUserQuestion`).

### Tests

* Every new behaviour gets a test, and the suite must pass under every shell
  listed in the CI matrix.
* Keep logic testable by splitting it in two layers:
  * `find_*` and `normalize_*` take arguments, print a result, return non-zero
    on failure, and touch no globals.
  * `require_*` wrap those, assign the `ZIGM_*` globals, and exit on failure.
* Layout:
  * `tests/run.sh`, the runner, picks shells and reports totals.
  * `tests/lib.sh`, sourced by each test file, sources `zigm` with
    `ZIGM_LIB=1` and defines the assertions.
  * `tests/test_*.sh`, one file per area, ending in a call to `run_tests`.
* A test file's `test_*` functions each run in their own subshell, so a test
  may redefine functions such as `have` or `tar` to stub out the environment.
* Tests must not touch the network or the real home directory. End to end
  tests go through `zigm_run`, which points `HOME` and the directory overrides
  at scratch space.

### Git

* Never push, even if asked.
* Commit only when told to.
* When told to commit staged files, commit only what is staged. Do not stage
  anything extra.
* Ask before any modifying git operation.
* Use an `Assisted-By: <model>` trailer on commits.
* Write commit subjects in the conventional commits style,
  `<type>(<optional scope>): <description>`:
  * Types in use: `feat`, `fix`, `docs`, `test`, `ci`, `build`, `refactor`,
    `perf`, `style`, `chore`.
  * The description is imperative, lowercase, and carries no trailing period.
  * A breaking change takes a `!` before the colon, as in `feat!: drop the
    old layout`, and explains itself in the body.
  * The body is optional, wrapped at 72 columns, and explains why rather than
    what.

### TODO.md

* `TODO.md` holds the working state as a flat list of markdown todo items:
  * `- [ ] ` not yet started
  * `- [>] ` in progress
  * `- [X] ` completed
  * `- [-] ` will not be implemented
* Never delete items. Re-mark them instead.
* One sentence per item. Anything longer becomes nested sub-items, which may
  nest without limit.
* An item marked `- [>] ` always has sub-items explaining the progress.
* If an item genuinely cannot be broken down further, up to 3 single sentence
  non-todo bullets may be added.

### Doc style

Applies to all documentation, including comments and README.

* No em-dashes. Use colons, commas, or rephrase.
* No flashy or sensational language.
* No all caps for emphasis. Use italics in the rare cases emphasis is needed.
* No bold bullet point headers. Do not write `**Some header:** Explanation`.
* Prefer, as appropriate:
  * `* Explanation`
  * `* Some header, explanation`
  * `* Some header:` followed by an indented `* Explanation`
* Use bullet points generously.
* Keep text to 80 columns.
