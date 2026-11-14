#!/usr/bin/env python3
"""Rewrite hardcoded runtime SONAMEs in debian/control from installed -dev packages.

Distro stanzas like ``#forky: ,libopenjph0.28`` go stale on rolling forky while
dpkg-shlibdeps emits the SONAME that was actually linked. Both then appear in
Depends and the package is uninstallable.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


def dpkg_query(fmt: str, pkg: str) -> str:
    try:
        return subprocess.check_output(
            ["dpkg-query", "-W", "-f", fmt, pkg],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return ""


def installed_lib_dev_packages() -> list[str]:
    out = subprocess.check_output(
        ["dpkg-query", "-W", "-f", "${Package} ${Status}\n"],
        text=True,
    )
    names = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        name, status = parts[0], parts[-1]
        if status == "installed" and name.startswith("lib") and name.endswith("-dev"):
            names.append(name)
    return names


def runtime_packages_for_dev(dev: str) -> list[str]:
    prefix = dev[: -len("-dev")]
    deps = dpkg_query("${Depends}", dev)
    found = []
    for m in re.finditer(r"([A-Za-z0-9][A-Za-z0-9.+-]*)\s*\(", deps):
        pkg = m.group(1)
        if pkg.startswith(prefix) and not pkg.endswith("-dev"):
            found.append(pkg)
    return found


def rewrite(control: str) -> str:
    text = control
    for dev in installed_lib_dev_packages():
        prefix = dev[: -len("-dev")]
        runtimes = runtime_packages_for_dev(dev)
        if not runtimes:
            continue
        pattern = re.compile(
            r"(?<![\w.+-])" + re.escape(prefix) + r"(?:-?[0-9][0-9.]*)?"
        )

        def repl(match: re.Match[str]) -> str:
            tok = match.group(0)
            if tok == prefix or tok in runtimes:
                return tok
            print(
                f"debian/control: {tok} -> {runtimes[0]} (from {dev})",
                file=sys.stderr,
            )
            return runtimes[0]

        text = pattern.sub(repl, text)
    return text


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "debian/control")
    original = path.read_text()
    updated = rewrite(original)
    if updated != original:
        path.write_text(updated)
        print(f"rewrote runtime SONAMEs in {path}")
    else:
        print(f"runtime SONAMEs in {path} already match installed -dev packages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
