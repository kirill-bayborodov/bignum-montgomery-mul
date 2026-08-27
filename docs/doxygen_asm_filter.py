#!/usr/bin/env python3
"""Expose YASM file/symbol documentation to Doxygen without parsing instructions as C."""
from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    for raw in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith(";"):
            print("//" + line[1:])
        elif line == "global bignum_template":
            print("void bignum_template(void);")
        else:
            print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
