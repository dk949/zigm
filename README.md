# zigm

A Zig toolchain manager: a single POSIX shell script that fetches matched `zig`
and `zls` versions and exposes one of them on `PATH`.

* Installs a zig release together with the zls build that pairs with it.
* Keeps every installed version side by side, switching with one symlink swap.
* Handles tagged releases and the `master` nightly.
* One file, no build step, no shell integration.

## Requirements

* A POSIX shell, `sh`. The script is tested under dash, bash, mksh, ksh,
  busybox ash, and zsh.
* `curl` or `wget`, whichever is present.
* `tar` with xz support, or `tar` plus a separate `xz`.
* `jq`.
* Typical POSIX utilities: `awk`, `grep`, `sed`, and similar.
* Optional, for checksum verification: one of `sha256sum`, `shasum`, `openssl`,
  or a `cksum` that takes `-a sha256`. With none of them present zigm warns
  loudly and installs anyway.

Each command checks the tools it needs before doing any work, so a missing
dependency fails immediately rather than halfway through an install.

## Install

zigm is one file. Put it anywhere on your `PATH` and make it executable:

```sh
curl -fsSLo ~/.local/bin/zigm \
    https://raw.githubusercontent.com/dk949/zigm/main/zigm
chmod +x ~/.local/bin/zigm
```

Or clone the repo and link the script:

```sh
git clone https://github.com/dk949/zigm
ln -s "$PWD/zigm/zigm" ~/.local/bin/zigm
```

## PATH setup

zigm does not touch your shell configuration. Activation is a single directory
symlink, `current`, which points at the version in use. You put that directory
on `PATH` yourself, once:

```sh
# Linux and BSD
export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/zigm/current:$PATH"

# macOS
export PATH="$HOME/Library/Application Support/zigm/current:$PATH"
```

Add that line to your shell's startup file. Nothing else has to change when you
switch versions: `zigm use` repoints the symlink, and the path stays the same.

If you set `ZIGM_DATA_DIR`, use `$ZIGM_DATA_DIR/current` instead.

## Usage

```
zigm [global options] <command> [arguments]
```

### Commands

* `install <version>`
    * Install a zig and zls pair and activate it. The version is a tag such as
      `0.15.1`, or `master` for the nightly.
* `use <version>`
    * Point `current` at an already installed version.
* `uninstall <version>`
    * Remove an installed version. Removing the active one drops the `current`
      link and warns.
* `list`
    * List installed versions, oldest first, starring the active one.
* `list-remote`
    * List the upstream versions that have a build for this platform, marking
      an installed one with `i` and the active one with `*`.
* `which [name]`
    * Print the path of an active binary, `zig` by default.
* `current`
    * Print the active version.
* `update`
    * Install `master` at whatever version it resolves to now.
* `clean`
    * Remove the cache directory.

### Install and update options

* `--no-zls`
    * Install zig alone rather than failing when no zls pairs with it.
* `--no-use`
    * Install without activating the version. `install` only.
* `--force`
    * Reinstall a version that is already installed.

### Global options

* `-h`, `--help`, print help and exit.
* `-V`, `--version`, print the zigm version and exit.
* `-v`, `--verbose`, print debug output on stderr.
* `-q`, `--quiet`, print errors and warnings only.
* `--refresh`, refetch the download index even when a cached copy is fresh.

### Environment

* `ZIGM_DATA_DIR`, override the data directory.
* `ZIGM_CACHE_DIR`, override the cache directory.
* `ZIGM_CONFIG_DIR`, override the config directory.
* `ZIGM_INDEX_TTL`, seconds a cached download index stays fresh, 3600 by
  default.

### Exit codes

* `0` success
* `1` error
* `2` usage error

## Examples

```sh
zigm install 0.15.1          # install and activate a tagged release
zigm install master          # install tonight's nightly
zigm install 0.14.1 --no-use # install without switching to it
zigm use 0.14.1              # switch
zigm list                    # see what is installed
zigm current                 # 0.14.1
zigm which zls               # path to the active zls
zigm update                  # move master forward
zigm uninstall 0.14.1        # remove a version
```

## How it works

* Versions live in `<data>/zigm/versions/<version>/`, each holding the `zig` and
  `zls` binaries next to zig's `lib` directory, since zig locates that directory
  relative to its own path.
* `<data>/zigm/current` is a symlink to one of those directories. Switching is a
  single symlink swap, so a version is never partly active.
* An install is assembled in a scratch directory and moved into place with a
  rename, so a version directory is never half written. A reinstall moves the
  old directory aside and puts it back if the swap fails.
* Downloads are checked against the checksum upstream publishes for them. A
  mismatch is fatal; having nothing to compare against is a warning.
* zig versions come from the ziglang.org download index, cached in the cache
  directory for `ZIGM_INDEX_TTL` seconds.
* zls versions come from the zigtools version selection API, which pairs zig
  and zls for tagged and nightly builds alike. That answer is not cached, since
  a pairing is cheap to fetch and expensive to get wrong.
* `master` is a pointer, not a version. It resolves at install time and is
  stored under the concrete version it named, for example `0.16.0-dev.123+abc`.
  Old nightlies stay until you uninstall them, and `zigm use master` is
  therefore an error that tells you to name a version from `zigm list`.
* `update` follows `current` to the new nightly only when `current` pointed at a
  nightly already, or when nothing was active, so a pinned release is never
  moved out from under you.

## Directories

Platform native, honoring the XDG environment variables where they apply:

* Linux and BSD:
    * data: `${XDG_DATA_HOME:-~/.local/share}/zigm`
    * cache: `${XDG_CACHE_HOME:-~/.cache}/zigm`
    * config: `${XDG_CONFIG_HOME:-~/.config}/zigm`
* macOS:
    * data and config: `~/Library/Application Support/zigm`
    * cache: `~/Library/Caches/zigm`

Only the data and cache directories are written to. The config directory is
resolved ahead of a config file landing.

## Development

* There is no build step.
* Lint, which must be clean at `style` severity:
    * `shellcheck -S style zigm tests/*.sh`
* Syntax check without executing:
    * `sh -n zigm`
* Test:
    * `tests/run.sh` runs the suite under `sh`
    * `SHELLS='dash bash mksh ksh busybox zsh' tests/run.sh` runs it under each
      named shell, syntax checking `zigm` under that shell first
    * `tests/run.sh tests/test_dirs.sh` runs one file
* The tests never touch the network or the real home directory.
* CI runs shellcheck and the full matrix on Linux and macOS.

## Not implemented yet

* Version aliases.
* A config file.
* Minisign signature verification.

## License

MIT, see [LICENSE](LICENSE).
