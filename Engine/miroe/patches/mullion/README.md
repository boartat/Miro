# Mullion patches

On [Mullion](https://github.com/dttdrv/mullion) at the commit in `../../sources.conf` (`mullion`), in order.

| Patch | What it does |
| --- | --- |
| `0001` | The ARM64X link fix from Hadron's `patches/dxmt/0003`, unchanged: link libmingwex first so `__icall_helper_arm64ec` is not defined twice with Wine 11.21+ |
| `0002` | MUMA v2 ported from DXMT (`../dxmt/0001`-`0003`): spares of dynamic resources are trimmed by a thread per command queue, purgeable while idle, and freed under Mullion's memory budget. A purgeable spare leaves the residency heartbeat's set while it is one |

Results are in `../../RESEARCH.md` ("MUMA on Mullion"). LGPL-2.1-or-later like Mullion, written with AI assistance. Mullion's CONTRIBUTING accepts reviewed AI-assisted changes, but nothing here has been submitted.
