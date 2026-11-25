#!/usr/bin/env python3
"""Turns the title's sampling-profiler log lines into a table: where each thread spends its time.

Make the log: create an empty file named "profile" in the title's data folder on the console
(/data/homebrew/PPSA99777/data/), play for a minute or two, copy dirt2.log off.

Run inside the build container (it needs llvm-nm and the linked title):

    python3 profile_report.py dirt2.log [--min-busy=80] [/build/game/ps5-obj/title/llvm-pie.elf]

--min-busy=N keeps only the 20 s reports in which the busiest thread used at least N% of a core
(for example the race itself, not the menus).

Every "prof: tid N (entry E name) P% code|wait ADDR" line is one 64-byte block of code where a
thread was sampled: "code" means the thread was running title code there, "wait" that it was
inside the system (a lock, the kernel, a file) and ADDR is the title code that called it. Blocks
are named by the function that holds them, and grouped into layers: the recompiled game
("game", named f_<guest address>), the runtime and Windows shims, DXVK, and everything else.
"""
import re
import subprocess
import sys
from collections import defaultdict

args = [a for a in sys.argv[1:] if not a.startswith("--")]
min_busy = next((float(a.split("=")[1]) for a in sys.argv[1:] if a.startswith("--min-busy=")), 0.0)
log_path = args[0]
elf = args[1] if len(args) > 1 else "/build/game/ps5-obj/title/llvm-pie.elf"
lines = open(log_path, errors="replace").read().splitlines()

anchor = next((re.search(r"is at (?:0x)?([0-9a-f]+)", l).group(1) for l in lines if "prof: sampling started" in l), None)
if anchor is None:
    sys.exit("no 'prof: sampling started' line: was the file named 'profile' in the data folder?")
# The function holding an address is the symbol just below it in the ELF's symbol table (not
# llvm-symbolizer's innermost inlined frame, which names helpers instead of the function).
nm = subprocess.run(["llvm-nm", "-C", "-n", "--defined-only", elf], capture_output=True, text=True).stdout
symbols = []  # (address, name), by address
for l in nm.splitlines():
    parts = l.split(None, 2)
    if len(parts) == 3 and parts[1] in ("T", "t", "W", "w"):
        symbols.append((int(parts[0], 16), parts[2]))
starts = [a for a, _ in symbols]
base = next((a for a, n in symbols if n == "rt::start_profiler()"), None)
if base is None:
    sys.exit("start_profiler not found in " + elf)
slide = int(anchor, 16) - base

pat = re.compile(r"prof: tid (\d+) \(entry ([0-9A-F]+) ([^)]*)\)\s+([\d.]+)% (code|wait) ([0-9a-f]+)")
rows = []
reports = 0
keep = True
for l in lines:
    c = re.search(r"\] cpu: .*busiest: tid \d+\([^)]*\) (\d+)%", l)
    if c:  # the cpu line opens a report: its busiest thread decides whether the report counts
        keep = float(c.group(1)) >= min_busy
        reports += keep
        continue
    m = pat.search(l)
    if m and keep:
        rows.append((int(m.group(1)), m.group(2), m.group(3).strip(), float(m.group(4)), m.group(5), int(m.group(6), 16) - slide))
reports = reports or 1
if not rows:
    sys.exit("no 'prof:' sample lines in the log")

import bisect


def name_of(addr):
    k = bisect.bisect_right(starts, addr) - 1
    return symbols[k][1] if k >= 0 else "??"


names = {a: name_of(a) for a in {r[5] for r in rows}}


def layer(name):
    if name == "??":
        return "unknown"
    if re.match(r"^f_[0-9A-Fa-f]{6,8}", name):
        return "game (recompiled)"
    if "dxvk::" in name:
        return "DXVK"
    if re.search(r"\baco::|\bnir_|radv_|\bac_|ac::", name):
        return "GPU driver (RADV shader compiler and driver)"
    if name.startswith("rt::") or "rt::" in name.split("(")[0]:
        return "runtime (memory, threads, dispatch)"
    if "(X86*" in name:
        return "shims (the game's Windows, D3D and sound calls)"
    return "other (libc, SDL, kernel)"


# Per thread: the title's own samples, averaged over the reports (a block missing from a report counts 0).
threads = defaultdict(lambda: {"entry": "", "name": "", "blocks": defaultdict(float)})
for tid, entry, name, pct, kind, addr in rows:
    t = threads[tid]
    t["entry"], t["name"] = entry, name
    t["blocks"][(kind, names.get(addr, "??"))] += pct / reports
print("%d profile reports (20 s each); percentages are of that thread's samples, averaged\n" % reports)
def code_share(t):
    return sum(pct for (kind, _), pct in t["blocks"].items() if kind == "code")


idle = [tid for tid, t in threads.items() if code_share(t) < 5]
if idle:
    print("%d threads were waiting nearly all the time (under 5%% of samples running title code): %s\n" % (
        len(idle), ", ".join(str(i) for i in sorted(idle))))
for tid, t in sorted(threads.items(), key=lambda kv: -code_share(kv[1])):
    total = sum(t["blocks"].values())
    if code_share(t) < 5:
        continue
    print("thread %d (entry %s %s): %.0f%% of samples running title code, %.0f%% waiting in the system" % (tid, t["entry"], t["name"], code_share(t), total - code_share(t)))
    by_layer = defaultdict(float)
    for (kind, name), pct in t["blocks"].items():
        by_layer[(kind, layer(name))] += pct
    for (kind, lay), pct in sorted(by_layer.items(), key=lambda kv: -kv[1]):
        print("    %5.1f%%  %-4s  %s" % (pct, kind, lay))
    print("  hottest functions:")
    for (kind, name), pct in sorted(t["blocks"].items(), key=lambda kv: -kv[1])[:18]:
        print("    %5.1f%%  %-4s  %s" % (pct, kind, name[:90]))
    print()
