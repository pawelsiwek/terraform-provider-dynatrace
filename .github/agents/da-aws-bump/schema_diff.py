#!/usr/bin/env python3
"""schema_diff.py — deterministic structural diff of two extension schemas.

Reads two JSON schemas from disk, walks them via JSON Pointer paths, and
emits a stable diff to stdout with shape:

    {
      "old_version": "1.0.7",
      "new_version": "1.0.8",
      "added":    [ { "path": "/properties/...", "after":  {...} }, ... ],
      "modified": [ { "path": "/properties/...", "before": {...},
                                                  "after":  {...} }, ... ],
      "removed":  [ { "path": "/properties/...", "before": {...} }, ... ]
    }

Only schema-relevant nodes are considered (`properties`, `items`,
`enum`, `type`, `required`, `deprecated`). The diff is *structural*, not
textual — key reordering or whitespace differences in the source schema
do not produce noise.

Usage:
    schema_diff.py <old.json> <new.json> <old_version> <new_version>
"""

from __future__ import annotations

import json
import sys
from typing import Any


SCHEMA_KEYS = ("type", "enum", "required", "deprecated", "description")


def walk(node: Any, path: str, out: dict[str, dict]) -> None:
    """Flatten a schema into {jsonpointer: {type,enum,required,deprecated,...}}."""
    if not isinstance(node, dict):
        return

    leaf = {k: node[k] for k in SCHEMA_KEYS if k in node}
    if leaf:
        out[path] = leaf

    props = node.get("properties")
    if isinstance(props, dict):
        required = set(node.get("required") or [])
        for name, sub in props.items():
            sub_path = f"{path}/properties/{name}"
            if isinstance(sub, dict):
                sub_leaf = {k: sub[k] for k in SCHEMA_KEYS if k in sub}
                sub_leaf["required"] = name in required
                out[sub_path] = sub_leaf
            walk(sub, sub_path, out)

    items = node.get("items")
    if isinstance(items, dict):
        walk(items, f"{path}/items", out)


def main() -> int:
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        return 2

    with open(sys.argv[1], encoding="utf-8") as f:
        old = json.load(f)
    with open(sys.argv[2], encoding="utf-8") as f:
        new = json.load(f)

    old_flat: dict[str, dict] = {}
    new_flat: dict[str, dict] = {}
    walk(old, "", old_flat)
    walk(new, "", new_flat)

    old_keys = set(old_flat)
    new_keys = set(new_flat)

    added = sorted(new_keys - old_keys)
    removed = sorted(old_keys - new_keys)
    modified = sorted(k for k in old_keys & new_keys if old_flat[k] != new_flat[k])

    result = {
        "old_version": sys.argv[3],
        "new_version": sys.argv[4],
        "added":    [{"path": p, "after":  new_flat[p]} for p in added],
        "modified": [{"path": p, "before": old_flat[p],
                                  "after":  new_flat[p]} for p in modified],
        "removed":  [{"path": p, "before": old_flat[p]} for p in removed],
    }
    json.dump(result, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
