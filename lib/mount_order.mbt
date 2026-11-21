///|
priv struct MountOrder {
  mount : Mount
  posix : String
  native : String
  posix_bytes : Int32
  native_bytes : Int32
  declaration : Int32
}

///|
fn mount_utf8_length(text : String) -> Int32 {
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
fn mount_byte_compare(left : String, right : String) -> Int32 {
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
fn ParsedPath::native_mount_name(self : ParsedPath) -> String {
  let native_root = match self.root {
    DriveAbsolute(drive) => drive + ":"
    Unc(server, share) => "\\\\" + server + "\\" + share
    _ => ""
  }
  if self.components.is_empty() {
    native_root
  } else {
    native_root + "\\" + self.components.join("\\")
  }
}

///|
fn MountOrder::new(mount : Mount, declaration : Int32) -> MountOrder {
  let posix = "/" + mount.posix.components.join("/")
  let native = mount.windows.native_mount_name()
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
fn mount_median(
  values : Array[MountOrder],
  a : Int32,
  b : Int32,
  c : Int32,
  compare : (MountOrder, MountOrder) -> Int32,
) -> Int32 {
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
fn mount_swap(values : Array[MountOrder], a : Int32, b : Int32) -> Unit {
  let value = values[a]
  values[a] = values[b]
  values[b] = value
}

///|
fn mount_insertion(
  values : Array[MountOrder],
  start : Int32,
  length : Int32,
  compare : (MountOrder, MountOrder) -> Int32,
) -> Unit {
  for i in (start + 1)..<(start + length) {
    let mut j = i
    while j > start && compare(values[j - 1], values[j]) > 0 {
      mount_swap(values, j, j - 1)
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
fn mount_qsort(
  values : Array[MountOrder],
  start : Int32,
  length : Int32,
  compare : (MountOrder, MountOrder) -> Int32,
) -> Unit {
  let mut start = start
  let mut length = length
  while length > 1 {
    if length < 7 {
      mount_insertion(values, start, length, compare)
      return
    }
    let mut middle = start + length / 2
    if length > 7 {
      let mut first = start
      let mut last = start + length - 1
      if length > 40 {
        let step = length / 8
        first = mount_median(
          values,
          first,
          first + step,
          first + 2 * step,
          compare,
        )
        middle = mount_median(
          values,
          middle - step,
          middle,
          middle + step,
          compare,
        )
        last = mount_median(values, last - 2 * step, last - step, last, compare)
      }
      middle = mount_median(values, first, middle, last, compare)
    }
    mount_swap(values, start, middle)
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
          mount_swap(values, left_equal, left)
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
          mount_swap(values, right, right_equal)
          right_equal -= 1
        }
        right -= 1
      }
      if left > right {
        break
      }
      mount_swap(values, left, right)
      swapped = true
      left += 1
      right -= 1
    }
    if !swapped {
      mount_insertion(values, start, length, compare)
      return
    }
    let left_swap = (left_equal - start).min(left - left_equal)
    for offset in 0..<left_swap {
      mount_swap(values, start + offset, left - left_swap + offset)
    }
    let end = start + length
    let right_swap = (right_equal - right).min(end - right_equal - 1)
    for offset in 0..<right_swap {
      mount_swap(values, left + offset, end - right_swap + offset)
    }
    let left_length = left - left_equal
    let right_length = right_equal - right
    // Recurse into the smaller partition, then iterate over the larger one.
    // This preserves the upstream processing order with logarithmic stack use.
    if right_length > left_length {
      mount_qsort(values, start, left_length, compare)
      start = end - right_length
      length = right_length
    } else {
      mount_qsort(values, end - right_length, right_length, compare)
      length = left_length
    }
  }
}

///|
fn MountOrder::tie(self : MountOrder, other : MountOrder) -> Int32 {
  // Both pinned comparators inspect the right-hand entry on an exact tie.
  // This is observable even with two aliases of the same ownership.
  match (self.mount.system, other.mount.system) {
    (Some(_), Some(system)) => if system { -1 } else { 1 }
    _ => self.declaration.compare(other.declaration)
  }
}

///|
fn runtime_mount_order(
  mounts : Array[Mount],
  profile : Profile,
  windows~ : Bool,
) -> Array[Int32] {
  let keys = mounts.mapi((i, mount) => MountOrder::new(mount, i))
  mount_qsort(keys, 0, keys.length(), (a, b) => {
    let (order, left, right) = match (profile, windows) {
      (Cygwin, false) =>
        (b.posix_bytes.compare(a.posix_bytes), a.posix, b.posix)
      (Cygwin, true) =>
        (b.native_bytes.compare(a.native_bytes), a.native, b.native)
      (Msys2, true) =>
        (
          (b.posix_bytes - b.native_bytes).compare(
            a.posix_bytes - a.native_bytes,
          ),
          a.posix,
          b.posix,
        )
      (Msys2, false) =>
        (a.native_bytes.compare(b.native_bytes), a.native, b.native)
    }
    if order != 0 {
      order
    } else {
      let by_name = mount_byte_compare(left, right)
      if by_name == 0 {
        a.tie(b)
      } else {
        by_name
      }
    }
  })
  if profile == Msys2 && !windows {
    mount_qsort(keys, 0, keys.length(), (a, b) => {
      if a.posix != b.posix && a.posix.has_prefix(b.posix) {
        -1
      } else if a.posix != b.posix && b.posix.has_prefix(a.posix) {
        1
      } else {
        0
      }
    })
  }
  keys.map(key => key.declaration)
}
