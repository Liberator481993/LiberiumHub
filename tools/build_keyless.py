#!/usr/bin/env python3
"""Build the executor-ready single-file Keyless from the modular v92 sources.

The source tree stays modular for development. This builder inlines the modules
inside local factories so the resulting Keyless has no ModuleScript require()
or remote framework dependency at runtime.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[1]


def read_text(relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.is_file():
        raise FileNotFoundError(f"required build input is missing: {relative_path}")
    return path.read_text(encoding="utf-8")


def wrap_module(local_name: str, source: str) -> str:
    return f"local {local_name} = (function()\n{source.rstrip()}\nend)()\n"


def build() -> str:
    base = read_text("src/legacy/Keyless.base.lua")
    maid = read_text("src/core/Maid.lua")
    theme = read_text("src/ui/Theme.lua")
    window = read_text("src/ui/Window.lua")
    adapter = read_text("src/ui/LegacyAdapter.lua")
    movement = read_text("src/features/Movement/MovementPlus.lua")

    start_marker = "local Win, Tab, Sub, Sec = {}, {}, {}, {}\n"
    end_marker = "local Config = ConfigManager.new()"
    start = base.find(start_marker)
    if start < 0:
        raise RuntimeError("could not locate the legacy UI renderer start marker in Keyless")
    end = base.find(end_marker, start)
    if end < 0:
        raise RuntimeError("could not locate the ConfigManager boundary after the legacy UI renderer")

    window = window.replace(
        "local ThemeFactory = require(script.Parent.Theme)",
        "local ThemeFactory = EmbeddedTheme",
        1,
    )
    window = window.replace(
        "local Maid = require(script.Parent.Parent.core.Maid)",
        "local Maid = EmbeddedMaid",
        1,
    )
    adapter = adapter.replace(
        "local Window = require(script.Parent.Window)",
        "local Window = EmbeddedWindow",
        1,
    )
    movement = movement.replace(
        "local Maid = require(script.Parent.Parent.Parent.core.Maid)",
        "local Maid = EmbeddedMaid",
        1,
    )

    embedded = [
        "-- v92 Nova UI modules are embedded for executor compatibility.",
        wrap_module("EmbeddedMaid", maid),
        wrap_module("EmbeddedTheme", theme),
        wrap_module("EmbeddedWindow", window),
        wrap_module("EmbeddedAdapter", adapter),
        wrap_module("EmbeddedMovementPlus", movement),
        "local MovementPlus = EmbeddedMovementPlus",
        "local Lib = EmbeddedAdapter.create(EmbeddedWindow)",
        "",
    ]

    result = base[:start] + "\n".join(embedded) + base[end:]
    result = re.sub(
        r"^-- LIBERIUM HUB \| .*?$",
        "-- LIBERIUM HUB | v92 | NOVA UI + PULSEHUB FEATURE PORT",
        result,
        count=1,
        flags=re.MULTILINE,
    )
    result = result.replace("v91.70", "v92")
    if "require(script.Parent" in result:
        raise RuntimeError("generated Keyless still contains a ModuleScript require()")
    if "local Win, Tab, Sub, Sec" in result:
        raise RuntimeError("legacy renderer was not completely replaced")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="replace the root Keyless file instead of writing dist/Keyless",
    )
    parser.add_argument(
        "--output",
        default="dist/Keyless",
        help="output path relative to repository root (default: dist/Keyless)",
    )
    args = parser.parse_args()

    try:
        output = ROOT / "Keyless" if args.in_place else ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        result = build()
        output.write_text(result, encoding="utf-8", newline="\n")
        try:
            display_path = output.relative_to(ROOT)
        except ValueError:
            display_path = output
        print(f"Built {display_path} ({len(result):,} characters)")
        return 0
    except Exception as error:  # noqa: BLE001 - build tool must report actionable errors
        print(f"build failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
