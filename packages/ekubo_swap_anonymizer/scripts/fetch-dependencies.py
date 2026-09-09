#!/usr/bin/env python3
"""Avoid Scarb 2.20's concurrent first checkout of the privacy workspace's utils."""
import pathlib
import subprocess
import tempfile
import tomllib
import urllib.parse

PACKAGE = pathlib.Path(__file__).resolve().parents[1]
lock = tomllib.loads((PACKAGE / "Scarb.lock").read_text())
utils = next(package for package in lock["package"] if package["name"] == "starkware_utils")
source = urllib.parse.urlsplit(utils["source"].removeprefix("git+"))

# The privacy workspace discovers this same Git source through multiple packages.
# Warm just that source first so those concurrent readers find a complete checkout.
with tempfile.TemporaryDirectory(prefix="ekubo-scarb-fetch-") as directory:
    root = pathlib.Path(directory)
    (root / "src").mkdir()
    (root / "src/lib.cairo").write_text("")
    (root / "Scarb.toml").write_text(
        '[package]\nname = "ekubo_dependency_bootstrap"\nversion = "0.1.0"\n'
        '[dependencies]\n'
        f'starkware_utils = {{ git = "{source.scheme}://{source.netloc}{source.path}", '
        f'rev = "{source.fragment}" }}\n'
    )
    subprocess.run(["scarb", "--manifest-path", str(root / "Scarb.toml"), "fetch"], check=True)
subprocess.run(["scarb", "--manifest-path", str(PACKAGE / "Scarb.toml"), "fetch"], check=True)
