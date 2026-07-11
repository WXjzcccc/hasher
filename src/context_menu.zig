const std = @import("std");
const builtin = @import("builtin");
const hash = @import("hash/core.zig");

const HKey = *opaque {};
const hkey_current_user: HKey = @ptrFromInt(@as(usize, 0x80000001));
const key_write: u32 = 0x0002_0006;
const key_read: u32 = 0x0002_0019;
const reg_sz: u32 = 1;

extern "advapi32" fn RegCloseKey(key: ?HKey) callconv(.winapi) i32;
extern "advapi32" fn RegCreateKeyExW(
    parent: ?HKey,
    subkey: [*:0]const u16,
    reserved: u32,
    class: ?[*:0]u16,
    options: u32,
    desired_access: u32,
    security_attributes: ?*const anyopaque,
    result: *?HKey,
    disposition: ?*u32,
) callconv(.winapi) i32;
extern "advapi32" fn RegSetValueExW(
    key: ?HKey,
    value_name: ?[*:0]const u16,
    reserved: u32,
    value_type: u32,
    data: ?*const u8,
    data_size: u32,
) callconv(.winapi) i32;
extern "advapi32" fn RegOpenKeyExW(parent: ?HKey, subkey: [*:0]const u16, options: u32, desired_access: u32, result: *?HKey) callconv(.winapi) i32;
extern "advapi32" fn RegQueryValueExW(key: ?HKey, value_name: ?[*:0]const u16, reserved: ?*u32, value_type: ?*u32, data: ?*u8, data_size: ?*u32) callconv(.winapi) i32;
extern "advapi32" fn RegDeleteValueW(key: ?HKey, value_name: ?[*:0]const u16) callconv(.winapi) i32;
extern "advapi32" fn RegDeleteTreeW(parent: ?HKey, subkey: [*:0]const u16) callconv(.winapi) i32;
extern "kernel32" fn GetModuleFileNameW(module: ?*anyopaque, path: [*]u16, capacity: u32) callconv(.winapi) u32;
extern "shell32" fn SHChangeNotify(event_id: c_long, flags: c_uint, item1: ?*const anyopaque, item2: ?*const anyopaque) callconv(.winapi) void;

const MenuItem = struct {
    key: []const u8,
    algorithm: ?hash.Algorithm,
};

const menu_items = [_]MenuItem{
    .{ .key = "crc32", .algorithm = .crc32 },
    .{ .key = "crc64-iso", .algorithm = .crc64_iso },
    .{ .key = "crc64-ecma", .algorithm = .crc64_ecma },
    .{ .key = "md5", .algorithm = .md5 },
    .{ .key = "sha1", .algorithm = .sha1 },
    .{ .key = "sha256", .algorithm = .sha256 },
    .{ .key = "sha512", .algorithm = .sha512 },
    .{ .key = "sm3", .algorithm = .sm3 },
    .{ .key = "all", .algorithm = null },
};

const registry_targets = [_][]const u8{
    "Software\\Classes\\*\\shell\\Hasher",
    "Software\\Classes\\Directory\\shell\\Hasher",
};

pub const ContextHashRequest = struct {
    options: hash.HashOptions,
    path: []const u8,
};

pub fn parseContextHashArgs(args: []const []const u8) ?ContextHashRequest {
    if (args.len != 4 or !std.mem.eql(u8, args[1], "--context-hash")) return null;
    if (std.ascii.eqlIgnoreCase(args[2], "ALL")) return .{ .options = hash.HashOptions.all(), .path = args[3] };
    for (hash.all_algorithms) |algorithm| {
        if (std.ascii.eqlIgnoreCase(args[2], algorithm.label())) {
            return .{ .options = hash.HashOptions.only(algorithm), .path = args[3] };
        }
    }
    return null;
}

/// Registers a per-user Explorer submenu. The command launches the current
/// executable and immediately begins calculating the selected file or folder.
pub fn install(allocator: std.mem.Allocator) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

    const exe_path = try currentExecutablePath(allocator);
    defer allocator.free(exe_path);

    for (registry_targets) |target| try installTarget(allocator, target, exe_path);
    notifyExplorer();
}

pub fn uninstall(allocator: std.mem.Allocator) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;
    for (registry_targets) |target| {
        const target_z = try std.unicode.utf8ToUtf16LeAllocZ(allocator, target);
        defer allocator.free(target_z);
        const result = RegDeleteTreeW(hkey_current_user, target_z.ptr);
        if (result != 0 and result != 2) return error.RegistryWriteFailed;
    }
    notifyExplorer();
}

pub fn isInstalled(allocator: std.mem.Allocator) bool {
    if (builtin.os.tag != .windows) return false;
    for (registry_targets) |target| {
        if (!hasStringValue(allocator, target, "SubCommands")) return false;
    }
    return true;
}

fn currentExecutablePath(allocator: std.mem.Allocator) ![]u8 {
    var path: [32_768]u16 = undefined;
    const length = GetModuleFileNameW(null, &path, path.len);
    if (length == 0 or length >= path.len) return error.ExecutablePathUnavailable;
    return std.unicode.utf16LeToUtf8Alloc(allocator, path[0..length]);
}

fn installTarget(allocator: std.mem.Allocator, target: []const u8, exe_path: []const u8) !void {
    try deleteDefaultValue(allocator, target);
    try writeString(allocator, target, "MUIVerb", "Hasher");
    try writeString(allocator, target, "Icon", exe_path);
    try writeString(allocator, target, "MultiSelectModel", "Player");
    try writeString(allocator, target, "SubCommands", "");

    for (menu_items) |item| {
        const item_path = try std.fmt.allocPrint(allocator, "{s}\\shell\\{s}", .{ target, item.key });
        defer allocator.free(item_path);
        const label = if (item.algorithm) |algorithm|
            try std.fmt.allocPrint(allocator, "计算 {s}", .{algorithm.label()})
        else
            try allocator.dupe(u8, "计算全部算法");
        defer allocator.free(label);
        try writeString(allocator, item_path, null, label);

        const command_path = try std.fmt.allocPrint(allocator, "{s}\\command", .{item_path});
        defer allocator.free(command_path);
        const argument = if (item.algorithm) |algorithm| algorithm.label() else "ALL";
        const command = try std.fmt.allocPrint(allocator, "\"{s}\" --context-hash {s} \"%1\"", .{ exe_path, argument });
        defer allocator.free(command);
        try writeString(allocator, command_path, null, command);
    }
}

fn deleteDefaultValue(allocator: std.mem.Allocator, path: []const u8) !void {
    const path_z = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path);
    defer allocator.free(path_z);
    var key: ?HKey = null;
    if (RegCreateKeyExW(hkey_current_user, path_z.ptr, 0, null, 0, key_write, null, &key, null) != 0) return error.RegistryWriteFailed;
    defer _ = RegCloseKey(key);
    const result = RegDeleteValueW(key, null);
    if (result != 0 and result != 2) return error.RegistryWriteFailed;
}

fn hasStringValue(allocator: std.mem.Allocator, path: []const u8, value_name: []const u8) bool {
    const path_z = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return false;
    defer allocator.free(path_z);
    const name_z = std.unicode.utf8ToUtf16LeAllocZ(allocator, value_name) catch return false;
    defer allocator.free(name_z);
    var key: ?HKey = null;
    if (RegOpenKeyExW(hkey_current_user, path_z.ptr, 0, key_read, &key) != 0) return false;
    defer _ = RegCloseKey(key);
    var value_type: u32 = 0;
    var size: u32 = 0;
    return RegQueryValueExW(key, name_z.ptr, null, &value_type, null, &size) == 0 and value_type == reg_sz;
}

fn notifyExplorer() void {
    const shcne_assocchanged: c_long = 0x0800_0000;
    const shcnf_idlist: c_uint = 0;
    SHChangeNotify(shcne_assocchanged, shcnf_idlist, null, null);
}

fn writeString(allocator: std.mem.Allocator, path: []const u8, value_name: ?[]const u8, value: []const u8) !void {
    const path_z = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path);
    defer allocator.free(path_z);
    const name_z = if (value_name) |name| try std.unicode.utf8ToUtf16LeAllocZ(allocator, name) else null;
    defer if (name_z) |name| allocator.free(name);
    const value_z = try std.unicode.utf8ToUtf16LeAllocZ(allocator, value);
    defer allocator.free(value_z);

    var key: ?HKey = null;
    if (RegCreateKeyExW(hkey_current_user, path_z.ptr, 0, null, 0, key_write, null, &key, null) != 0) return error.RegistryWriteFailed;
    defer _ = RegCloseKey(key);

    const value_size = @as(u32, @intCast((value_z.len + 1) * @sizeOf(u16)));
    if (RegSetValueExW(key, if (name_z) |name| name.ptr else null, 0, reg_sz, @ptrCast(value_z.ptr), value_size) != 0) {
        return error.RegistryWriteFailed;
    }
}

test "parses a supported context-menu request" {
    const request = parseContextHashArgs(&.{ "hasher.exe", "--context-hash", "SHA256", "C:\\file.txt" }).?;
    try std.testing.expect(request.options.sha256);
    try std.testing.expect(!request.options.md5);
    try std.testing.expectEqualStrings("C:\\file.txt", request.path);
}

test "parses the all-algorithms context-menu request" {
    const request = parseContextHashArgs(&.{ "hasher.exe", "--context-hash", "ALL", "C:\\file.txt" }).?;
    inline for (hash.all_algorithms) |algorithm| try std.testing.expect(request.options.enabled(algorithm));
}

test "rejects incomplete context-menu requests" {
    try std.testing.expect(parseContextHashArgs(&.{ "hasher.exe", "--context-hash", "SHA256" }) == null);
}
