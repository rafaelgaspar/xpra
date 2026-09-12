# xpra-rafaelgaspar-overlay

Small Debian package applied **after** the xpra.org apt stack. Ships forked Python
modules and (optionally) the fork HTML5 client tree.

## Why not a full xpra rebuild?

Upstream splits one source into many binaries (`xpra-common`, `xpra-x11`,
`xpra-server`, …) with `Depends: (= ${binary:Version})` between them. A proper
fork release would mirror that whole set. This overlay keeps xpra.org binaries and
only replaces the files we patch.

## Upgrade safety

`preinst`/`prerm` use **`dpkg-divert`** so xpra.org upgrades write to `*.distrib`
instead of overwriting the forked paths.

`control` pins the base stack:

- `Depends: xpra-server (>= <upstream>), xpra-x11 (>= <upstream>), xpra-common (>= <upstream>)`
- `Breaks` below the built-for upstream floor (`<< <upstream>`)
- `Replaces` (including `xpra-html5` when bundling HTML5) for file ownership

Package **name** is `xpra-rafaelgaspar-overlay`. **Version** matches the integration
release tag without `v` (e.g. `6.5.3-rafaelgaspar.9` for `v6.5.3-rafaelgaspar.9`;
`6.5.3-rafaelgaspar` for the first build on that upstream base).
`Depends`/`Breaks` floors still use the upstream xpra semver (`6.5.3`).

Rebuild and reinstall this package whenever the xpra.org base version changes.

## Build

```sh
./packaging/rafaelgaspar-overlay/build-deb.sh \
  6.5.3-rafaelgaspar.9 \
  6.5.3 \
  dist/xpra-html5-20-rafaelgaspar.14.tar.gz \
  20
```
