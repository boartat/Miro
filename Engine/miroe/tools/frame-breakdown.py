#!/usr/bin/env python3
"""Where a Wine process under Rosetta spends its CPU time, from an Instruments Time Profiler trace.

    frame-breakdown.py --samples samples.xml --vmmap vmmap.txt

For a Rosetta-translated process Instruments records the address of the translated code that ran, not the
original x86 address. This script finds which memory region each address is in, using `vmmap` of the
same process (profile.sh collects both):

- `<library>.aot` mappings: Mac libraries Rosetta translated ahead of time (Wine's Unix side, DXMT's
  winemetal.so, MoltenVK, the x86 system libraries). The file name gives the original library.
- "Rosetta JIT": code Rosetta translates while running. Under Wine that is the Windows code: the game,
  every PE DLL (Wine's and the graphics translator's Windows side) and .NET JIT code.
- /usr/libexec/rosetta/runtime: Rosetta itself (translation and dispatch).
- Addresses inside the x86 system shared cache's span that vmmap lists no image for: Rosetta's translation
  of the shared cache, i.e. macOS libraries and frameworks, Metal and the GPU driver included. In a
  translated process these run as translated x86 code too.

Each running sample is counted once, by the code on top of its stack (self time).
"""
import argparse
import bisect
import collections
import re
import xml.etree.ElementTree as ET

LIBRARY_LAYERS = [
    ("Wine Unix side", ("ntdll.so", "win32u.so", "winemac.so", "winevulkan.so", "winecoreaudio.so",
                        "winebus.so", "ws2_32.so", "wine")),
    ("Graphics translator, Unix side", ("winemetal.so", "libd3dshared", "D3DMetal", "libMoltenVK",
                                        "libvulkan", "libdxmt")),
    ("macOS libraries and frameworks (incl. Metal)", ("dyld_shared_cache", "libsystem", "dyld", "libobjc",
                                                       "libc++", "Metal", "AGX")),
]
SHARED_CACHE = "macOS frameworks incl. Metal and GPU driver (translated shared cache)"
REGION = re.compile(r"^(.+?)\s+([0-9a-f]{6,})-([0-9a-f]{6,})\s+\[[^\]]*\]\s+\S+\s+(?:SM=\S+\s+)?(.*)$")


def regions_of(path):
    regions = []
    for line in open(path, errors="replace"):
        match = REGION.match(line.rstrip())
        if match:
            kind, start, end, detail = match.groups()
            regions.append((int(start, 16), int(end, 16), kind.strip(), detail.strip()))
    regions.sort()
    return regions


def classify(kind, detail):
    """(layer, finer name) of a vmmap region"""
    path = detail.split()[-1] if detail else ""
    name = path.rsplit("/", 1)[-1]
    if path.endswith("/rosetta/runtime"):
        return "Rosetta runtime (translation, dispatch)", "rosetta runtime"
    if kind.startswith("Rosetta JIT"):
        return "Windows code: game, PE DLLs, .NET (Rosetta JIT)", "Rosetta JIT"
    if kind.startswith("Rosetta"):
        return "Rosetta runtime (translation, dispatch)", kind
    if name.endswith(".aot"):
        library = name[:-4]
        for layer, keys in LIBRARY_LAYERS:
            if any(library == k or library.startswith(k) for k in keys):
                return layer, library
        return "Other Mac library", library
    return "Other (%s)" % kind, name or kind


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", required=True)
    parser.add_argument("--vmmap", required=True)
    args = parser.parse_args()

    regions = regions_of(args.vmmap)
    starts = [r[0] for r in regions]
    cache = [r for r in regions if r[2] == "__TEXT" and r[3].split()[-1:] and
             r[3].split()[-1].startswith(("/System/", "/usr/lib/"))]
    cache_low = min((r[0] for r in cache), default=0)
    cache_high = max((r[1] for r in cache), default=0)
    root = ET.parse(args.samples).getroot()
    by_id = {e.attrib["id"]: e for e in root.iter() if "id" in e.attrib}

    def resolve(element):
        if element is not None and "ref" in element.attrib:
            return by_id.get(element.attrib["ref"])
        return element

    layers, names, threads = collections.Counter(), collections.Counter(), collections.Counter()
    per_thread = collections.defaultdict(collections.Counter)
    total = 0
    for row in root.iter("row"):
        state = resolve(row.find("thread-state"))
        if state is not None and state.attrib.get("fmt") != "Running":
            continue
        backtrace = resolve(row.find("tagged-backtrace"))
        if backtrace is None:
            backtrace = resolve(row.find("backtrace"))
        if backtrace is None:
            continue
        frames = [resolve(f) for f in backtrace.findall("frame")]
        if not frames or frames[0] is None:
            continue
        address = int(frames[0].attrib.get("addr", "0"), 16)
        i = bisect.bisect_right(starts, address) - 1
        if i >= 0 and address < regions[i][1]:
            layer, name = classify(regions[i][2], regions[i][3])
        elif cache_low <= address < cache_high:
            layer, name = SHARED_CACHE, "translated shared cache"
        else:
            layer, name = "Not in the memory map", "?"
        layers[layer] += 1
        names[name] += 1
        thread = resolve(row.find("thread"))
        thread_name = thread.attrib.get("fmt", "?").split(" (")[0] if thread is not None else "?"
        threads[thread_name] += 1
        per_thread[thread_name][layer] += 1
        total += 1

    if not total:
        print("no running samples")
        return
    print("running samples: %d (1 ms each)\n" % total)
    print("by layer (self time)")
    for name, count in layers.most_common():
        print("  %5.1f%%  %s" % (100.0 * count / total, name))
    print("\nby library")
    for name, count in names.most_common(12):
        print("  %5.1f%%  %s" % (100.0 * count / total, name))
    print("\nby thread (and its biggest layers)")
    for name, count in threads.most_common(6):
        parts = ", ".join("%s %.0f%%" % (layer.split(" (")[0], 100.0 * n / count)
                          for layer, n in per_thread[name].most_common(3))
        print("  %5.1f%%  %s: %s" % (100.0 * count / total, name, parts))


if __name__ == "__main__":
    main()
