///|
test "all UTF-16 mount uppercase mappings match the Windows NLS reference" {
  // FNV-1a over the little-endian uppercase words from l_intl.nls.
  // The build, file SHA-256 and table SHA-256 are in third_party/microsoft.
  let mut hash = 2166136261U
  for unit in 0..<65536 {
    let upper = mount_upper(unit).reinterpret_as_uint()
    hash = (hash ^ (upper & 255)) * 16777619U
    hash = (hash ^ (upper >> 8)) * 16777619U
  }
  assert_eq(hash, 0xbc467f47U)
}
