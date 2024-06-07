# Zig SCALE Codec

Zig implementation of the SCALE (Simple Concatenated Aggregate Little-Endian)

_Ensure you have installed zig 0.12.0._

### Executing tests from source

After cloning the repository you can run:

```sh
zig build test
```

### Roadmap

Currently support the encode og the following types

| Type                                                              | Encode | Decode |
| ----------------------------------------------------------------- | ------ | ------ |
| Fixed Integers (i8, i16, i32, i64, i128, u8, u16, u32, u64, u128) | ✅     | ❌     |
| Compact Integers                                                  | ✅     | ❌     |
| Boolean                                                           | ✅     | ✅     |
| Options                                                           | ✅     | ❌     |
| Strings                                                           | ✅     | ❌     |
| Structs                                                           | ✅     | ❌     |
| Results                                                           | ✅     | ❌     |
| Fixed Size Arrays                                                 | ✅     | ❌     |
| Slices                                                            | ✅     | ❌     |
| Tuples                                                            | ✅     | ❌     |
| Enumerations (tagged-unions)                                      | ✅     | ❌     |
