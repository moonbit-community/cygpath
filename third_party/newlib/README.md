# newlib sorting attribution

The private `mount_qsort`, median selection, swap, and insertion helpers in
`lib/mount_order.mbt` adapt the BSD-3-Clause sorting implementation from
[newlib `qsort.c`](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/newlib/libc/search/qsort.c).
The copyright notice, conditions, and disclaimer are retained in
[LICENSE.txt](LICENSE.txt) and must accompany binary distributions.

The pinned source SHA-256 is
`99aa392d3ce6781035014af0d16ffd2f6a97f31b014320316b7b5706ddcf73dc`.

The adaptation uses MoonBit array indices and element swaps, replaces the
upstream parameter stack with smaller-partition recursion, and keeps pivot
selection, equal-element placement, and the insertion-sort fallback. These
details are observable because the MSYS2 mount ancestry comparator is not a
total order. No upstream C code is compiled or linked into the product.

The mount comparison rules are independently implemented from the behavior in
[the same pinned runtime's `mount.cc`](https://github.com/msys2/msys2-runtime/blob/c770e1b9fa537fff9287c1fd40ebc84ac498fcb6/winsup/cygwin/mount.cc).
Both pinned runtimes use the same newlib sorter. An installation snapshot
starts with fstab insertion order and uses the ownership comparison when names
tie. Cygwin sorts by descending byte length and then byte spelling in each
direction. MSYS2 applies its own directional comparisons. Explicit mounts
without ownership retain their declared priority on exact ties.
[Cygwin comparison functions](https://github.com/cygwin/cygwin/blob/b11613e477c006b2ce0332463ed07f1118260e79/winsup/cygwin/mount.cc#L1372-L1454)
