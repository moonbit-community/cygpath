///|
priv struct MsysMountOrder {
  mount : Mount
  posix : String
  native : String
  posix_bytes : Int
  native_bytes : Int
  declaration : Int
}

///|
fn mount_utf8_length(text : String) -> Int {
  let mut length = 0
  for character in text {
    let code = character.to_int()
    length += if code < 0x80 {
      1
    } else if code < 0x800 {
      2
    } else if code < 0x10000 {
      3
    } else {
      4
    }
  }
  length
}

///|
fn mount_byte_compare(left : String, right : String) -> Int {
  // UTF-8 byte order agrees with scalar order, unlike UTF-16 code-unit order
  // across the BMP/supplementary boundary.
  let left = left.iter().to_array()
  let right = right.iter().to_array()
  for i in 0..<left.length().min(right.length()) {
    let order = left[i].to_int().compare(right[i].to_int())
    if order != 0 {
      return order
    }
  }
  left.length().compare(right.length())
}

///|
fn msys_mount_order(mount : Mount, declaration : Int) -> MsysMountOrder {
  let posix = "/" + mount.posix.components.join("/")
  let native_root = match mount.windows.root {
    DriveAbsolute(drive) => drive + ":"
    Unc(server, share) => "\\\\" + server + "\\" + share
    _ => ""
  }
  let native = if mount.windows.components.is_empty() {
    native_root
  } else {
    native_root + "\\" + mount.windows.components.join("\\")
  }
  {
    mount,
    posix,
    native,
    posix_bytes: mount_utf8_length(posix),
    native_bytes: mount_utf8_length(native),
    declaration,
  }
}

///|
fn msys_mount_median(
  values : Array[MsysMountOrder],
  a : Int,
  b : Int,
  c : Int,
  compare : (MsysMountOrder, MsysMountOrder) -> Int,
) -> Int {
  if compare(values[a], values[b]) < 0 {
    if compare(values[b], values[c]) < 0 {
      b
    } else if compare(values[a], values[c]) < 0 {
      c
    } else {
      a
    }
  } else if compare(values[b], values[c]) > 0 {
    b
  } else if compare(values[a], values[c]) < 0 {
    a
  } else {
    c
  }
}

///|
fn msys_mount_swap(values : Array[MsysMountOrder], a : Int, b : Int) -> Unit {
  let value = values[a]
  values[a] = values[b]
  values[b] = value
}

///|
fn msys_mount_insertion(
  values : Array[MsysMountOrder],
  start : Int,
  length : Int,
  compare : (MsysMountOrder, MsysMountOrder) -> Int,
) -> Unit {
  for i in (start + 1)..<(start + length) {
    let mut j = i
    while j > start && compare(values[j - 1], values[j]) > 0 {
      msys_mount_swap(values, j, j - 1)
      j -= 1
    }
  }
}

///|
// Adapted to MoonBit element indices from newlib's BSD-3-Clause qsort.c.
// Copyright (c) 1992, 1993 The Regents of the University of California.
// All rights reserved. Full notice and license: third_party/newlib/LICENSE.txt.
// Pinned source and adaptation details: third_party/newlib/README.md.
//
// The pivot, equal-element swaps, and insertion-sort fallback are observable
// here: MSYS2's second comparator returns equality for unrelated mount names.
// A general-purpose stable sort cannot replace this algorithm.
fn msys_mount_qsort(
  values : Array[MsysMountOrder],
  start : Int,
  length : Int,
  compare : (MsysMountOrder, MsysMountOrder) -> Int,
) -> Unit {
  let mut start = start
  let mut length = length
  while length > 1 {
    if length < 7 {
      msys_mount_insertion(values, start, length, compare)
      return
    }
    let mut middle = start + length / 2
    if length > 7 {
      let mut first = start
      let mut last = start + length - 1
      if length > 40 {
        let step = length / 8
        first = msys_mount_median(
          values,
          first,
          first + step,
          first + 2 * step,
          compare,
        )
        middle = msys_mount_median(
          values,
          middle - step,
          middle,
          middle + step,
          compare,
        )
        last = msys_mount_median(
          values,
          last - 2 * step,
          last - step,
          last,
          compare,
        )
      }
      middle = msys_mount_median(values, first, middle, last, compare)
    }
    msys_mount_swap(values, start, middle)
    let mut left_equal = start + 1
    let mut left = left_equal
    let mut right = start + length - 1
    let mut right_equal = right
    let mut swapped = false
    while true {
      while left <= right {
        let order = compare(values[left], values[start])
        if order > 0 {
          break
        }
        if order == 0 {
          swapped = true
          msys_mount_swap(values, left_equal, left)
          left_equal += 1
        }
        left += 1
      }
      while left <= right {
        let order = compare(values[right], values[start])
        if order < 0 {
          break
        }
        if order == 0 {
          swapped = true
          msys_mount_swap(values, right, right_equal)
          right_equal -= 1
        }
        right -= 1
      }
      if left > right {
        break
      }
      msys_mount_swap(values, left, right)
      swapped = true
      left += 1
      right -= 1
    }
    if !swapped {
      msys_mount_insertion(values, start, length, compare)
      return
    }
    let left_swap = (left_equal - start).min(left - left_equal)
    for offset in 0..<left_swap {
      msys_mount_swap(values, start + offset, left - left_swap + offset)
    }
    let end = start + length
    let right_swap = (right_equal - right).min(end - right_equal - 1)
    for offset in 0..<right_swap {
      msys_mount_swap(values, left + offset, end - right_swap + offset)
    }
    let left_length = left - left_equal
    let right_length = right_equal - right
    // Recurse into the smaller partition, then iterate over the larger one.
    // This preserves the upstream processing order with logarithmic stack use.
    if right_length > left_length {
      msys_mount_qsort(values, start, left_length, compare)
      start = end - right_length
      length = right_length
    } else {
      msys_mount_qsort(values, end - right_length, right_length, compare)
      length = left_length
    }
  }
}

///|
fn msys_ordered_mounts(mounts : Array[Mount], windows~ : Bool) -> Array[Mount] {
  let keys = mounts.mapi((i, mount) => msys_mount_order(mount, i))
  if windows {
    keys.sort_by((a, b) => {
      let order = (b.posix_bytes - b.native_bytes).compare(
        a.posix_bytes - a.native_bytes,
      )
      if order == 0 {
        mount_byte_compare(a.posix, b.posix)
      } else {
        order
      }
    })
  } else {
    msys_mount_qsort(keys, 0, keys.length(), (a, b) => {
      let length_order = a.native_bytes.compare(b.native_bytes)
      let order = if length_order == 0 {
        mount_byte_compare(a.native, b.native)
      } else {
        length_order
      }
      // The explicit context has no user/system provenance. Equal native
      // aliases retain the supplied context priority before the second sort.
      if order == 0 {
        a.declaration.compare(b.declaration)
      } else {
        order
      }
    })
    msys_mount_qsort(keys, 0, keys.length(), (a, b) => {
      if a.posix != b.posix && a.posix.has_prefix(b.posix) {
        -1
      } else if a.posix != b.posix && b.posix.has_prefix(a.posix) {
        1
      } else {
        0
      }
    })
  }
  keys.map(key => key.mount)
}
