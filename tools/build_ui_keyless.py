#!/usr/bin/env python3
"""Build the executor-ready Keyless using only the modular visual UI layer.

Gameplay code is read from src/legacy/Keyless.base.lua and is not rewritten.
The UI modules are embedded into the existing Lib.new/AddTab/AddSubTab/
AddSection/control API so the final script remains a single-file loadstring.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def read_text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

def wrap_module(name: str, source: str) -> str:
    return f"local {name} = (function()\n{source.rstrip()}\nend)()\n"

def build() -> str:
    base = read_text("src/legacy/Keyless.base.lua")
    maid = read_text("src/core/Maid.lua")
    theme = read_text("src/ui/Theme.lua")
    window = read_text("src/ui/Window.lua")
    adapter = read_text("src/ui/LegacyAdapter.lua")
    start_marker = "local Win, Tab, Sub, Sec = {}, {}, {}, {}\n"
    end_marker = "local Config = ConfigManager.new()"
    start = base.find(start_marker)
    end = base.find(end_marker, start)
    if start < 0 or end < 0:
        raise RuntimeError("could not locate the legacy UI renderer boundaries")
    window = window.replace("local ThemeFactory = require(script.Parent.Theme)", "local ThemeFactory = EmbeddedTheme", 1)
    window = window.replace("local Maid = require(script.Parent.Parent.core.Maid)", "local Maid = EmbeddedMaid", 1)
    adapter = adapter.replace("local Window = require(script.Parent.Window)", "local Window = EmbeddedWindow", 1)
    adapter = adapter.replace("v92 • NOVA", "v93 • NOVA")
    embedded = [
        "-- v93 Nova UI modules are embedded for executor compatibility.",
        wrap_module("EmbeddedMaid", maid),
        wrap_module("EmbeddedTheme", theme),
        wrap_module("EmbeddedWindow", window),
        wrap_module("EmbeddedAdapter", adapter),
        "local Lib = EmbeddedAdapter.create(EmbeddedWindow)\n",
        "",
    ]
    result = base[:start] + "\n".join(embedded) + base[end:]
    result = re.sub(r"^-- LIBERIUM HUB \| .*?$", "-- LIBERIUM HUB | v93 | NOVA UI + PULSEHUB VISUAL PORT", result, count=1, flags=re.MULTILINE)
    result = result.replace("v91.70", "v93")
    if "require(script.Parent" in result:
        raise RuntimeError("generated Keyless still contains a ModuleScript require()")
    if start_marker in result:
        raise RuntimeError("legacy UI renderer was not completely replaced")
    return result

def main() -> int:
    output = ROOT / "Keyless"
    try:
        result = build()
        output.write_text(result, encoding="utf-8", newline="\n")
        print(f"Built Keyless ({len(result):,} characters)")
        return 0
    except Exception as error:
        print(f"build failed: {error}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
