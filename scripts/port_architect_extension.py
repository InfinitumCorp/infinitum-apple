#!/usr/bin/env python3
"""Builds the Safari copy of the :\\ARCHITECT\\ extension from InfinitumCorp/architect.

    git clone --depth 1 https://github.com/InfinitumCorp/architect.git /tmp/architect
    python3 scripts/port_architect_extension.py /tmp/architect
    python3 scripts/generate.py

Copies architect/extension into Extensions/Architect/Resources and adapts it for Safari:
the side panel becomes the toolbar popup, Chrome-only permissions are dropped, and the shim in
Extensions/Architect/safari/ is loaded first in every page and in the background.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Extensions" / "Architect" / "Resources"
SHIM = ROOT / "Extensions" / "Architect" / "safari"
SKIP = {"README.md", "i18n.config.json"}


def main(src_repo: str) -> int:
    src = Path(src_repo) / "extension"
    if not (src / "manifest.json").exists():
        print(f"No extension/manifest.json under {src_repo}", file=sys.stderr)
        return 1
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(src, OUT, ignore=lambda d, names: [n for n in names if n in SKIP and Path(d) == src])
    for name in ("safari-shim.js", "safari-background.js", "safari.css"):
        shutil.copy(SHIM / name, OUT / "src" / name)

    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    manifest.pop("side_panel", None)
    manifest.pop("minimum_chrome_version", None)
    perms = [p for p in manifest.get("permissions", []) if p not in ("sidePanel", "identity")]
    if "tabs" not in perms:
        perms.append("tabs")
    manifest["permissions"] = perms
    manifest.setdefault("action", {})["default_popup"] = "src/panel.html"
    manifest["browser_specific_settings"] = {"safari": {"strict_min_version": "17.0"}}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    bg = OUT / "src" / "background.js"
    bg.write_text('import "./safari-shim.js";\nimport "./safari-background.js";\n' + bg.read_text(encoding="utf-8"), encoding="utf-8")

    for page in ("panel.html", "options.html"):
        path = OUT / "src" / page
        html = path.read_text(encoding="utf-8")
        first_script = html.index("<script")
        inject = '<script type="module" src="safari-shim.js"></script>\n  '
        if page == "panel.html":
            inject = '<link rel="stylesheet" href="safari.css" />\n  ' + inject
        path.write_text(html[:first_script] + inject + html[first_script:], encoding="utf-8")

    print(f"Safari extension written to {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "../architect"))
