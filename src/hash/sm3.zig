const std = @import("std");

pub const digest_length = 32;
pub const block_length = 64;

const iv = [8]u32{
    0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600,
    0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e,
};

pub const Sm3 = struct {
    state: [8]u32 = iv,
    buffer: [block_length]u8 = undefined,
    buffer_len: usize = 0,
    total_len: u64 = 0,

    pub fn init() Sm3 {
        return .{};
    }

    pub fn update(self: *Sm3, input: []const u8) void {
        var data = input;
        self.total_len += data.len;

        if (self.buffer_len > 0) {
            const take = @min(block_length - self.buffer_len, data.len);
            @memcpy(self.buffer[self.buffer_len .. self.buffer_len + take], data[0..take]);
            self.buffer_len += take;
            data = data[take..];
            if (self.buffer_len == block_length) {
                self.compress(&self.buffer);
                self.buffer_len = 0;
            }
        }

        while (data.len >= block_length) {
            self.compress(data[0..block_length]);
            data = data[block_length..];
        }

        if (data.len > 0) {
            @memcpy(self.buffer[0..data.len], data);
            self.buffer_len = data.len;
        }
    }

    pub fn final(self: *Sm3, out: *[digest_length]u8) void {
        const bit_len = self.total_len * 8;
        self.buffer[self.buffer_len] = 0x80;
        self.buffer_len += 1;

        if (self.buffer_len > 56) {
            @memset(self.buffer[self.buffer_len..], 0);
            self.compress(&self.buffer);
            self.buffer_len = 0;
        }

        @memset(self.buffer[self.buffer_len..56], 0);
        std.mem.writeInt(u64, self.buffer[56..64], bit_len, .big);
        self.compress(&self.buffer);

        for (self.state, 0..) |word, i| {
            std.mem.writeInt(u32, out[i * 4 ..][0..4], word, .big);
        }
    }

    fn compress(self: *Sm3, block: *const [block_length]u8) void {
        var w: [68]u32 = undefined;
        var w1: [64]u32 = undefined;

        for (0..16) |i| {
            w[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .big);
        }
        for (16..68) |j| {
            w[j] = p1(w[j - 16] ^ w[j - 9] ^ rotl(w[j - 3], 15)) ^ rotl(w[j - 13], 7) ^ w[j - 6];
        }
        for (0..64) |j| {
            w1[j] = w[j] ^ w[j + 4];
        }

        var a = self.state[0];
        var b = self.state[1];
        var c = self.state[2];
        var d = self.state[3];
        var e = self.state[4];
        var f = self.state[5];
        var g = self.state[6];
        var h = self.state[7];

        for (0..64) |j| {
            const tj: u32 = if (j < 16) 0x79cc4519 else 0x7a879d8a;
            const ss1 = rotl(rotl(a, 12) +% e +% rotl(tj, @intCast(j & 31)), 7);
            const ss2 = ss1 ^ rotl(a, 12);
            const tt1 = ff(j, a, b, c) +% d +% ss2 +% w1[j];
            const tt2 = gg(j, e, f, g) +% h +% ss1 +% w[j];
            d = c;
            c = rotl(b, 9);
            b = a;
            a = tt1;
            h = g;
            g = rotl(f, 19);
            f = e;
            e = p0(tt2);
        }

        self.state[0] ^= a;
        self.state[1] ^= b;
        self.state[2] ^= c;
        self.state[3] ^= d;
        self.state[4] ^= e;
        self.state[5] ^= f;
        self.state[6] ^= g;
        self.state[7] ^= h;
    }
};

fn rotl(x: u32, n: u5) u32 {
    return std.math.rotl(u32, x, n);
}

fn p0(x: u32) u32 {
    return x ^ rotl(x, 9) ^ rotl(x, 17);
}

fn p1(x: u32) u32 {
    return x ^ rotl(x, 15) ^ rotl(x, 23);
}

fn ff(j: usize, x: u32, y: u32, z: u32) u32 {
    return if (j < 16) x ^ y ^ z else (x & y) | (x & z) | (y & z);
}

fn gg(j: usize, x: u32, y: u32, z: u32) u32 {
    return if (j < 16) x ^ y ^ z else (x & y) | (~x & z);
}

test "sm3 abc" {
    var sm3 = Sm3.init();
    sm3.update("abc");
    var out: [digest_length]u8 = undefined;
    sm3.final(&out);
    const hex = std.fmt.bytesToHex(out, .lower);
    try std.testing.expectEqualStrings("66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0", &hex);
}
