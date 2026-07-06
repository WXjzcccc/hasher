const std = @import("std");
const sm3 = @import("sm3.zig");

pub const Algorithm = enum {
    md5,
    sha1,
    sha256,
    sha512,
    sm3,
    crc32,
    crc64_iso,
    crc64_ecma,

    pub fn label(self: Algorithm) []const u8 {
        return switch (self) {
            .md5 => "MD5",
            .sha1 => "SHA1",
            .sha256 => "SHA256",
            .sha512 => "SHA512",
            .sm3 => "SM3",
            .crc32 => "CRC32",
            .crc64_iso => "CRC64_ISO",
            .crc64_ecma => "CRC64_ECMA",
        };
    }
};

pub const algorithm_count = std.meta.fields(Algorithm).len;
pub const all_algorithms = std.enums.values(Algorithm);

pub const HashOptions = packed struct {
    md5: bool = false,
    sha1: bool = false,
    sha256: bool = true,
    sha512: bool = false,
    sm3: bool = false,
    crc32: bool = false,
    crc64_iso: bool = false,
    crc64_ecma: bool = false,

    pub fn enabled(self: HashOptions, algorithm: Algorithm) bool {
        return switch (algorithm) {
            .md5 => self.md5,
            .sha1 => self.sha1,
            .sha256 => self.sha256,
            .sha512 => self.sha512,
            .sm3 => self.sm3,
            .crc32 => self.crc32,
            .crc64_iso => self.crc64_iso,
            .crc64_ecma => self.crc64_ecma,
        };
    }

    pub fn set(self: *HashOptions, algorithm: Algorithm, value: bool) void {
        switch (algorithm) {
            .md5 => self.md5 = value,
            .sha1 => self.sha1 = value,
            .sha256 => self.sha256 = value,
            .sha512 => self.sha512 = value,
            .sm3 => self.sm3 = value,
            .crc32 => self.crc32 = value,
            .crc64_iso => self.crc64_iso = value,
            .crc64_ecma => self.crc64_ecma = value,
        }
    }

    pub fn any(self: HashOptions) bool {
        inline for (all_algorithms) |algorithm| {
            if (self.enabled(algorithm)) return true;
        }
        return false;
    }
};

pub const HashResult = struct {
    values: [algorithm_count][]u8 = [_][]u8{&.{}} ** algorithm_count,

    pub fn deinit(self: *HashResult, allocator: std.mem.Allocator) void {
        for (&self.values) |*value| {
            if (value.len > 0) allocator.free(value.*);
            value.* = &.{};
        }
    }

    pub fn get(self: HashResult, algorithm: Algorithm) []const u8 {
        return self.values[@intFromEnum(algorithm)];
    }
};

const Crc64Iso = std.hash.crc.Crc64GoIso;
const Crc64Ecma = std.hash.crc.Crc64Ecma182;

pub fn calculateFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    options: HashOptions,
    stop: *std.atomic.Value(bool),
) !HashResult {
    var file = try std.Io.Dir.openFileAbsolute(io, path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    var buffer = try allocator.alloc(u8, determineBufferSize(stat.size));
    defer allocator.free(buffer);

    var md5 = std.crypto.hash.Md5.init(.{});
    var sha1 = std.crypto.hash.Sha1.init(.{});
    var sha256 = std.crypto.hash.sha2.Sha256.init(.{});
    var sha512 = std.crypto.hash.sha2.Sha512.init(.{});
    var sm3_hash = sm3.Sm3.init();
    var crc32 = std.hash.crc.Crc32.init();
    var crc64_iso = Crc64Iso.init();
    var crc64_ecma = Crc64Ecma.init();
    var offset: u64 = 0;

    while (true) {
        if (stop.load(.acquire)) return error.Stopped;
        const n = try file.readPositional(io, &.{buffer}, offset);
        if (n == 0) break;
        offset += n;
        const chunk = buffer[0..n];
        if (options.md5) md5.update(chunk);
        if (options.sha1) sha1.update(chunk);
        if (options.sha256) sha256.update(chunk);
        if (options.sha512) sha512.update(chunk);
        if (options.sm3) sm3_hash.update(chunk);
        if (options.crc32) crc32.update(chunk);
        if (options.crc64_iso) crc64_iso.update(chunk);
        if (options.crc64_ecma) crc64_ecma.update(chunk);
    }

    var result = HashResult{};
    errdefer result.deinit(allocator);
    if (options.md5) result.values[@intFromEnum(Algorithm.md5)] = try digestHex(allocator, std.crypto.hash.Md5, &md5);
    if (options.sha1) result.values[@intFromEnum(Algorithm.sha1)] = try digestHex(allocator, std.crypto.hash.Sha1, &sha1);
    if (options.sha256) result.values[@intFromEnum(Algorithm.sha256)] = try digestHex(allocator, std.crypto.hash.sha2.Sha256, &sha256);
    if (options.sha512) result.values[@intFromEnum(Algorithm.sha512)] = try digestHex(allocator, std.crypto.hash.sha2.Sha512, &sha512);
    if (options.sm3) {
        var out: [sm3.digest_length]u8 = undefined;
        sm3_hash.final(&out);
        result.values[@intFromEnum(Algorithm.sm3)] = try bytesToHex(allocator, &out);
    }
    if (options.crc32) result.values[@intFromEnum(Algorithm.crc32)] = try intHex(allocator, u32, crc32.final());
    if (options.crc64_iso) result.values[@intFromEnum(Algorithm.crc64_iso)] = try intHex(allocator, u64, crc64_iso.final());
    if (options.crc64_ecma) result.values[@intFromEnum(Algorithm.crc64_ecma)] = try intHex(allocator, u64, crc64_ecma.final());
    return result;
}

fn digestHex(allocator: std.mem.Allocator, comptime Hasher: type, hasher: *Hasher) ![]u8 {
    var out: [Hasher.digest_length]u8 = undefined;
    hasher.final(&out);
    return bytesToHex(allocator, &out);
}

fn bytesToHex(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, i| {
        const encoded = std.fmt.bytesToHex([1]u8{byte}, .lower);
        out[i * 2] = encoded[0];
        out[i * 2 + 1] = encoded[1];
    }
    return out;
}

fn intHex(allocator: std.mem.Allocator, comptime T: type, value: T) ![]u8 {
    return try std.fmt.allocPrint(allocator, "{x:0>8}", .{value});
}

pub fn determineBufferSize(file_size: u64) usize {
    return switch (file_size) {
        0...10 * 1024 * 1024 => 512 * 1024,
        10 * 1024 * 1024 + 1...100 * 1024 * 1024 => 1024 * 1024,
        100 * 1024 * 1024 + 1...1024 * 1024 * 1024 => 2 * 1024 * 1024,
        1024 * 1024 * 1024 + 1...10 * 1024 * 1024 * 1024 => 8 * 1024 * 1024,
        else => 16 * 1024 * 1024,
    };
}

test "buffer sizing mirrors original thresholds" {
    try std.testing.expectEqual(@as(usize, 512 * 1024), determineBufferSize(10));
    try std.testing.expectEqual(@as(usize, 1024 * 1024), determineBufferSize(11 * 1024 * 1024));
    try std.testing.expectEqual(@as(usize, 2 * 1024 * 1024), determineBufferSize(101 * 1024 * 1024));
}
