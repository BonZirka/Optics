#!/usr/bin/env python3
"""Compare fused benchmark bodies with their reconstruction oracles.

This is an optional performance check for Cangjie 1.0 on Darwin arm64 at -O2,
not a portable correctness gate. Only local branch addresses and the Cangjie
stack-frame metadata pointer are normalized. All data accesses, calls, and
other instructions must agree.
"""

import argparse
import difflib
import os
from pathlib import Path
import re
import subprocess


def normalize(body):
    instructions = []
    for line in body.splitlines():
        match = re.match(r"^([0-9a-f]+):\s+(.*)", line)
        if match:
            # Objdump's nearest-symbol comments are not instruction operands.
            instructions.append((int(match[1], 16), match[2].split(" <")[0]))
    if not instructions:
        raise ValueError("empty disassembly")
    start, end = instructions[0][0], instructions[-1][0] + 4
    result = []
    for _, instruction in instructions:
        if re.match(r"(?:b(?:\.[a-z]+)?|cbz|cbnz|tbz|tbnz)\s", instruction):
            def branch(match):
                target = int(match[1], 16)
                return f"@{target - start:+x}" if start <= target < end else match[0]
            instruction = re.sub(r"0x([0-9a-f]+)", branch, instruction)
        result.append(instruction)

    # The prologue installs a different metadata record for each function.
    # Require the observed sequence; do not erase arbitrary address operands.
    if not (result[3] == "adr\tx9, #-12"
            and result[4].startswith("adrp\tx10, ")
            and result[5].startswith("add\tx10, x10, #")
            and "stp\tx10, x9, [x29, #-16]" in result[6:12]):
        raise ValueError("unrecognized Cangjie frame prologue; inspect manually")
    result[4:6] = ["adrp\tx10, <frame metadata>", "add\tx10, x10, <frame metadata>"]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--objdump", type=Path, default=Path(
        os.environ.get("CANGJIE_HOME", "")) / "third_party/llvm/bin/llvm-objdump")
    args = parser.parse_args()
    symbols = {
        shape: [f"__CN15tests.generated{len(shape) + 5}{shape}Bench{method}Hv"
                for method in ("6optics", "11reconstruct")]
        for shape in ("Enum8", "Enum8Hit", "BlockWidth8")
    }
    assembly = subprocess.check_output([
        str(args.objdump.resolve()), "-d", "--no-show-raw-insn",
        "--disassemble-symbols=" + ",".join(s for pair in symbols.values() for s in pair),
        str(args.binary),
    ], text=True)
    if "file format mach-o arm64" not in assembly:
        parser.error("this comparison currently supports Darwin arm64 binaries only")
    bodies = dict(re.findall(
        r"(?m)^[0-9a-f]+ <([^>]+)>:\n(.*?)(?=^[0-9a-f]+ <|\Z)", assembly, re.S))
    failed = False
    for shape, (optic, oracle) in symbols.items():
        left, right = normalize(bodies[optic]), normalize(bodies[oracle])
        if left != right:
            failed = True
            print("\n".join(difflib.unified_diff(
                right, left, fromfile=f"{shape}.reconstruct", tofile=f"{shape}.optics")))
        else:
            print(f"{shape}: identical ({len(left)} instructions, normalizing local branches and frame metadata)")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
