const hash = @import("hash/core.zig");

pub const clsid_string = "{B2C2D39A-61E7-4D19-9DD7-29A4D3E4D2B1}";

pub const menu_algorithms = [_]hash.Algorithm{
    .crc32,
    .crc64_iso,
    .crc64_ecma,
    .md5,
    .sha1,
    .sha256,
    .sha512,
    .sm3,
};

pub fn commandKey(algorithm: hash.Algorithm) []const u8 {
    return switch (algorithm) {
        .crc32 => "crc32",
        .crc64_iso => "crc64-iso",
        .crc64_ecma => "crc64-ecma",
        .md5 => "md5",
        .sha1 => "sha1",
        .sha256 => "sha256",
        .sha512 => "sha512",
        .sm3 => "sm3",
    };
}

pub const clsid = extern struct {
    data1: u32,
    data2: u16,
    data3: u16,
    data4: [8]u8,
};

pub const extension_clsid = clsid{
    .data1 = 0xB2C2D39A,
    .data2 = 0x61E7,
    .data3 = 0x4D19,
    .data4 = .{ 0x9D, 0xD7, 0x29, 0xA4, 0xD3, 0xE4, 0xD2, 0xB1 },
};
