# webkit-jhbuild

A jhbuild moduleset and configuration for building the set of third-party
dependencies needed to build WPE WebKit / WebKitGTK **without the
[WebKit Container SDK][wkdev-sdk]**, directly on the host.

This is the alternative to the WebKit Container SDK (`wkdev`), which does the
same but inside a container. The moduleset is kept in sync with the SDK's own
jhbuild definitions.

The instructions below assume a **Fedora 44** host.

## Layout

| Path | Purpose |
| --- | --- |
| `jhbuildrc` | jhbuild configuration (prefix, checkout/build/download dirs, compiler) |
| `webkit.modules` | The moduleset (a single file merging the SDK's `webkit-deps.modules` + `gstreamer.modules` + extras) |
| `build/` | Build directories (git-ignored) |
| `checkout/` | Source checkouts (git-ignored) |
| `downloads/` | Downloaded tarballs (git-ignored) |
| `install/` | jhbuild prefix (git-ignored) |
| `patches/` | Patches applied during the build |

`jhbuild` itself is installed separately (it is not part of this repository).

## Requirements

The host needs these tools to run `jhbuild build`. All are looked up on `PATH`
(or, for `meson`/`ninja`, used directly by jhbuild).

| Tool | Fedora package | Notes |
| --- | --- | --- |
| `meson` | `meson` | Also needed at WebKit build time |
| `ninja` | `ninja` | |
| `cmake` | `cmake` | For cmake-based modules (libwpe, openxr, monado, ...) |
| `autoconf` / `automake` / `libtool` | `autoconf automake libtool` | For autotools modules |
| `gettext` / `autopoint` | `gettext gettext-devel` | Autotools modules need the gettext m4 macros visible to `aclocal` |
| `gtkdocize` | `gtk-doc` | Only needed if any module runs `gtkdocize` |
| `cargo` / `rustc` | `rust cargo` | For `gst-plugins-rs` |
| `cargo-cbuild` | `cargo-c` | For `gst-plugins-rs` (provides `cargo-cbuild`) |
| `python3` | `python3` | |
| `bison` / `flex` | `bison flex` | |
| `pkg-config` | `pkgconfig-pkg-config` | |
| `git` | `git` | |

On a minimal Fedora host the missing pieces are usually:

```console
sudo dnf install meson ninja cmake autoconf automake libtool \
  gettext gettext-devel gtk-doc rust cargo cargo-c bison flex pkgconf-pkg-config git
```

### gettext m4 macros

`gettext-devel` installs `gettext.m4` under `gettext`'s private `m4/` directory
(`/usr/share/gettext/m4/`), which `aclocal` does not search by default. If
`jhbuild sanitycheck` reports `aclocal can't see gettext macros`, make the macro
visible:

```console
sudo ln -sf /usr/share/gettext/m4/gettext.m4 /usr/share/aclocal/gettext.m4
```

## Usage

A `Makefile` provides short `make` wrappers around jhbuild:

```console
make requirements   # installs Fedora packages (calls install-requirements-dnf)
make list           # list what would be built
make clean          # remove build/ and install/
make                # build
```

`make clean` removes `build/` and `install/` outright (a full clean). It does not
use `jhbuild clean`, which only runs `ninja clean` per module and errors on
modules whose build directory does not exist.

The `make` targets are thin wrappers; the underlying jhbuild invocation is
equivalent to running jhbuild by hand, pointing `-f` at this repository's
`jhbuildrc`:

```console
# List what would be built
jhbuild -f $this_work_copy_dir/jhbuildrc list

# Build
jhbuild -f $this_work_copy_dir/jhbuildrc --no-interact build

# Run a command under the jhbuild environment (PATH + PKG_CONFIG_PATH set up)
jhbuild -f $this_work_copy_dir/jhbuildrc run <command>
```

To build WebKit itself, check out WebKit (e.g. a worktree) and compile it inside
`jhbuild run`:

```console
git -C $webkit_checkout_dir worktree add $webkit_build_dir -b <branch>
jhbuild -f $this_work_copy_dir/jhbuildrc run bash -lc \
  'cd $webkit_build_dir && ./Tools/Scripts/build-webkit --release --wpe'
```

## Notes and gotchas

- **`meson` / `ninja` warnings**: `jhbuild list` prints
  `W: <module> has a dependency on unknown "meson" module` for every meson
  module. This is harmless — `meson`/`ninja` are host tools found via `PATH`
  (`meson` is simply missing from jhbuild's `virtual_sysdeps` list in the
  installed version).
- **gettext**: `jhbuild sanitycheck` may warn `aclocal can't see gettext macros`.
  Autotools-based modules (`dicts`, `libbacktrace`, ...) need the gettext m4
  macros on the host (see [Requirements](#requirements)).
- **CMake ≥ 3.5 policy**: libwpe's `CMakeLists.txt` declares
  `cmake_minimum_required(VERSION 3.0)`, which CMake 4.x rejects. `webkit.modules`
  passes `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` for libwpe to work around this.
- **`cargo-c`**: `gst-plugins-rs` needs the `cargo-cbuild` program, provided by the
  `cargo-c` package (see [Requirements](#requirements)).
- **Stale build dirs**: jhbuild skips the `configure` phase for a module whose
  `build/<module>` directory already exists, and then fails at `ninja` if
  `build.ninja` is missing. If a module fails during configure and is later fixed
  only in `webkit.modules`, delete `build/<module>` and rebuild
  (`jhbuild buildone <module>`) — `--force` alone only re-checks out, it does not
  re-run configure.
- **Stale `install/` collisions**: when bumping a library version (e.g. libsoup),
  jhbuild may leave the old version's `.so`/`.pc` under `install/`. That stale
  copy can then be picked up during the new build's GObject-introspection link,
  causing `undefined reference` errors. Remove the stale files under `install/`
  (and `install/_jhbuild/`) for that module before rebuilding.
- **System GStreamer clash**: gstreamer is built with `-Ddevtools=disabled` so it
  does not try to link `gst-validate` against a system-installed
  `libgstrtspserver`, which otherwise fails with an ABI mismatch (e.g. missing
  `gst_state_get_name`) when the host's gstreamer version differs from the one
  being built.
- **monado needs Eigen**: monado's bundled `FindEigen3.cmake` reads the Eigen
  version from a path that changed in Eigen 5.x, so `make` fails at monado's
  configure step on a host with Eigen 5. WebKit itself does not use monado (only
  openxr); build with `jhbuild ... build --skip=monado` if it is not needed.

## Keeping in sync with the SDK

The reference modulesets live in the SDK checkout, under
`images/wkdev_sdk/jhbuild/`:

- `webkit-deps.modules` — libwpe, wpebackend-fdo, sparkle-cdm, libsoup, openxr,
  gi-docgen, dicts
- `gstreamer.modules` — gstreamer 1.28.7, gst-plugins-rs, libspiel
- `extra-projects.modules` — glib, glib-networking, epiphany, nghttp2

`webkit.modules` here merges these into one file. When the SDK bumps a version,
port the corresponding version/tag/hash here.

[wkdev-sdk]: https://github.com/Igalia/webkit-container-sdk
