const std = @import("std");

pub const FileEntry = struct {
    path: []u8,
    name: []u8,
    size_label: []u8,
    size_bytes: u64,

    pub fn deinit(self: *FileEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.name);
        allocator.free(self.size_label);
    }
};

pub fn collect(allocator: std.mem.Allocator, io: std.Io, roots: []const []const u8) !std.ArrayList(FileEntry) {
    var entries = try std.ArrayList(FileEntry).initCapacity(allocator, 0);
    errdefer deinitEntries(&entries, allocator);
    for (roots) |root| {
        try collectOne(allocator, io, &entries, root);
    }
    return entries;
}

pub fn deinitEntries(entries: *std.ArrayList(FileEntry), allocator: std.mem.Allocator) void {
    for (entries.items) |*entry| entry.deinit(allocator);
    entries.deinit(allocator);
}

fn collectOne(allocator: std.mem.Allocator, io: std.Io, entries: *std.ArrayList(FileEntry), path: []const u8) !void {
    const stat = std.Io.Dir.cwd().statFile(io, path, .{ .follow_symlinks = false }) catch |err| {
        std.log.warn("stat failed for {s}: {}", .{ path, err });
        return;
    };
    switch (stat.kind) {
        .file => try appendFile(allocator, entries, path, stat.size),
        .directory => try walkDirectory(allocator, io, entries, path),
        .sym_link => {},
        else => {},
    }
}

fn walkDirectory(allocator: std.mem.Allocator, io: std.Io, entries: *std.ArrayList(FileEntry), root_path: []const u8) !void {
    var dir = std.Io.Dir.cwd().openDir(io, root_path, .{ .iterate = true }) catch |err| {
        std.log.warn("open dir failed for {s}: {}", .{ root_path, err });
        return;
    };
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |item| {
        if (item.kind == .sym_link) continue;
        const child_path = try std.fs.path.join(allocator, &.{ root_path, item.path });
        defer allocator.free(child_path);
        if (item.kind == .file) {
            const stat = std.Io.Dir.cwd().statFile(io, child_path, .{ .follow_symlinks = false }) catch continue;
            try appendFile(allocator, entries, child_path, stat.size);
        }
    }
}

fn appendFile(allocator: std.mem.Allocator, entries: *std.ArrayList(FileEntry), path: []const u8, size: u64) !void {
    const path_copy = try allocator.dupe(u8, path);
    errdefer allocator.free(path_copy);
    const base = std.fs.path.basename(path);
    const name_copy = try allocator.dupe(u8, base);
    errdefer allocator.free(name_copy);
    const size_label = try formatSize(allocator, size);
    errdefer allocator.free(size_label);
    try entries.append(allocator, .{
        .path = path_copy,
        .name = name_copy,
        .size_label = size_label,
        .size_bytes = size,
    });
}

pub fn formatSize(allocator: std.mem.Allocator, size: u64) ![]u8 {
    const kb = 1 << 10;
    const mb = 1 << 20;
    const gb = 1 << 30;
    const tb = 1 << 40;
    if (size >= tb) return std.fmt.allocPrint(allocator, "{d:.2} TB ({d} bytes)", .{ @as(f64, @floatFromInt(size)) / tb, size });
    if (size >= gb) return std.fmt.allocPrint(allocator, "{d:.2} GB ({d} bytes)", .{ @as(f64, @floatFromInt(size)) / gb, size });
    if (size >= mb) return std.fmt.allocPrint(allocator, "{d:.2} MB ({d} bytes)", .{ @as(f64, @floatFromInt(size)) / mb, size });
    if (size >= kb) return std.fmt.allocPrint(allocator, "{d:.2} KB ({d} bytes)", .{ @as(f64, @floatFromInt(size)) / kb, size });
    return std.fmt.allocPrint(allocator, "{d} bytes", .{size});
}
