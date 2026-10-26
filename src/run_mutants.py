#!/usr/bin/env python3
"""Inject one fault at a time into alu.v and check that tb_alu.v detects it.

Usage:  python3 run_mutants.py            (needs iverilog and vvp on PATH)
Run it in the folder containing alu.v and tb_alu.v. The original alu.v is never modified.
"""
import subprocess
import sys

SRC = open("alu.v").read()

# name -> (text to find in alu.v, replacement)
MUTANTS = {
    "ADD carry stuck at 0":            ("carry = sum_carry[16]; // ADD", "carry = 1'b0; // ADD"),
    "ADD overflow ignores sign match": ("overflow  = (a[15] == b[15]) && (out[15] != a[15]);",
                                        "overflow  = (out[15] != a[15]);"),
    "SUB carry inverted":              ("carry = sum_carry[16];\n                out = sum_carry[15:0];\n                overflow = (a[15] != b[15])",
                                        "carry = ~sum_carry[16];\n                out = sum_carry[15:0];\n                overflow = (a[15] != b[15])"),
    "SUB overflow wrong sign test":    ("overflow = (a[15] != b[15]) && (out[15] != a[15]);",
                                        "overflow = (a[15] == b[15]) && (out[15] != a[15]);"),
    "AND replaced by OR":              ("out = a & b;", "out = a | b;"),
    "XOR replaced by OR":              ("out = a ^ b;", "out = a | b;"),
    "SLL uses b[2:0]":                 ("a << b[3:0]", "a << b[2:0]"),
    "SRL uses b[2:0]":                 ("a >> b[3:0]", "a >> b[2:0]"),
    "SLL wrong at shift 15":           ("a << b[3:0]", "(b[3:0]==4'd15) ? 16'h0 : a << b[3:0]"),
    "SLT unsigned":                    ("($signed(a) < $signed(b))", "(a < b)"),
    "neg flag stuck at 0":             ("neg = out[15];", "neg = 1'b0;"),
    "zero flag inverted":              ("zero = (out == 16'b0);", "zero = (out != 16'b0);"),
}


def run(source):
    """Compile the (possibly mutated) ALU with tb_alu.v; return (passed, mismatches, invariants, x_faults)."""
    open("_mutant.v", "w").write(source)
    subprocess.run(["iverilog", "-g2012", "-o", "_msim", "_mutant.v", "tb_alu.v"], check=True)
    out = subprocess.run(["vvp", "_msim"], capture_output=True, text=True).stdout

    def count(label):
        for line in out.splitlines():
            if line.startswith(label):
                return int(line.split(":")[1])
        raise RuntimeError(f"'{label}' not found in simulator output")

    passed = "STATUS                 : PASSED" in out
    return (passed, count("Functional Mismatches"), count("Invariant Violations"), count("Input X/Z Faults"))


def main():
    ok, *_ = run(SRC)
    if not ok:
        sys.exit("Baseline (unmodified alu.v) does not pass; fix that first.")

    rows, caught, total = [], 0, 0
    for name, (old, new) in MUTANTS.items():
        if old not in SRC:
            print(f"SKIP  {name}  (pattern not found in alu.v)")
            continue
        total += 1
        _, mism, inv, xf = run(SRC.replace(old, new, 1))
        detected = (mism + inv + xf) > 0          # coverage holes alone do not count as detection
        caught += detected
        rows.append((name, "CAUGHT" if detected else "MISSED", mism, inv))

    width = max(len(r[0]) for r in rows)
    print(f"{'Injected fault':<{width}}  Result  Mismatches  Invariant hits")
    print("-" * (width + 36))
    for name, res, mism, inv in rows:
        print(f"{name:<{width}}  {res:<6}  {mism:>10}  {inv:>14}")
    print(f"\nDetected {caught} of {total} injected faults")

    with open("mutation_results.md", "w") as f:       # paste-ready table for the README
        f.write("| Injected fault | Result | Failing vectors |\n|---|---|---|\n")
        for name, res, mism, inv in rows:
            f.write(f"| {name} | {res} | {max(mism, inv)} |\n")
        f.write(f"\n**Detected {caught} of {total} injected faults.**\n")


if __name__ == "__main__":
    main()