const std = @import("std");
const builtin = @import("builtin");
const hash = @import("hash/core.zig");
const extension_shared = @import("context_extension_shared.zig");

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
extern "advapi32" fn RegDeleteTreeW(parent: ?HKey, subkey: [*:0]const u16) callconv(.winapi) i32;
extern "kernel32" fn GetModuleFileNameW(module: ?*anyopaque, path: [*]u16, capacity: u32) callconv(.winapi) u32;
extern "shell32" fn SHChangeNotify(event_id: c_long, flags: c_uint, item1: ?*const anyopaque, item2: ?*const anyopaque) callconv(.winapi) void;

const registry_targets = [_][]const u8{
    "Software\\Classes\\*\\shell\\Hasher",
    "Software\\Classes\\Directory\\shell\\Hasher",
};

pub const ContextHashRequest = struct {
    options: hash.HashOptions,
    paths: []const []const u8,
};

pub fn parseContextHashArgs(args: []const []const u8) ?ContextHashRequest {
    if (args.len < 4 or !std.mem.eql(u8, args[1], "--context-hash")) return null;
    if (std.ascii.eqlIgnoreCase(args[2], "ALL")) return .{ .options = hash.HashOptions.all(), .paths = args[3..] };
    for (hash.all_algorithms) |algorithm| {
        if (std.ascii.eqlIgnoreCase(args[2], algorithm.label())) {
            return .{ .options = hash.HashOptions.only(algorithm), .paths = args[3..] };
        }
    }
    return null;
}

pub fn optionsMask(options: hash.HashOptions) u8 {
    var mask: u8 = 0;
    for (hash.all_algorithms) |algorithm| {
        if (options.enabled(algorithm)) mask |= @as(u8, 1) << @intFromEnum(algorithm);
    }
    return mask;
}

pub fn optionsFromMask(mask: u8) hash.HashOptions {
    var options = hash.HashOptions.none();
    for (hash.all_algorithms) |algorithm| {
        options.set(algorithm, (mask & (@as(u8, 1) << @intFromEnum(algorithm))) != 0);
    }
    return options;
}

/// Registers an ExecuteCommand verb backed by the existing Hasher executable.
/// Explorer supplies the complete selection through IObjectWithSelection.
pub fn install(allocator: std.mem.Allocator) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;

    const exe_path = try currentExecutablePath(allocator);
    defer allocator.free(exe_path);
    if (registrationMatches(allocator, exe_path)) return;

    for (registry_targets) |target| try installTarget(allocator, target, exe_path);
    try installClassRegistration(allocator, exe_path);
    notifyExplorer();
}

pub fn uninstall(allocator: std.mem.Allocator) !void {
    if (builtin.os.tag != .windows) return error.UnsupportedPlatform;
    for (registry_targets) |target| try deleteTree(allocator, target);
    const clsid_path = try std.fmt.allocPrint(allocator, "Software\\Classes\\CLSID\\{s}", .{extension_shared.clsid_string});
    defer allocator.free(clsid_path);
    try deleteTree(allocator, clsid_path);
    notifyExplorer();
}

pub fn isInstalled(allocator: std.mem.Allocator) bool {
    if (builtin.os.tag != .windows) return false;
    for (registry_targets) |target| {
        if (!hasStringValue(allocator, target, "SubCommands")) return false;
    }
    // A legacy static registration also counts as enabled so startup can
    // migrate it in place without making the user toggle the setting twice.
    return true;
}

fn currentExecutablePath(allocator: std.mem.Allocator) ![]u8 {
    var path: [32_768]u16 = undefined;
    const length = GetModuleFileNameW(null, &path, path.len);
    if (length == 0 or length >= path.len) return error.ExecutablePathUnavailable;
    return std.unicode.utf16LeToUtf8Alloc(allocator, path[0..length]);
}

fn installTarget(allocator: std.mem.Allocator, target: []const u8, exe_path: []const u8) !void {
    try deleteTree(allocator, target);
    try writeString(allocator, target, "MUIVerb", "Hasher");
    try writeString(allocator, target, "Icon", exe_path);
    try writeString(allocator, target, "MultiSelectModel", "Player");
    try writeString(allocator, target, "SubCommands", "");

    inline for (extension_shared.menu_algorithms) |algorithm| {
        const label = try std.fmt.allocPrint(allocator, "计算 {s}", .{algorithm.label()});
        defer allocator.free(label);
        try installMenuItem(allocator, target, extension_shared.commandKey(algorithm), label);
    }
    try installMenuItem(allocator, target, "all", "计算全部算法");
}

fn installMenuItem(allocator: std.mem.Allocator, target: []const u8, key: []const u8, label: []const u8) !void {
    const item_path = try std.fmt.allocPrint(allocator, "{s}\\shell\\{s}", .{ target, key });
    defer allocator.free(item_path);
    try writeString(allocator, item_path, null, label);
    try writeString(allocator, item_path, "MultiSelectModel", "Player");
    const command_path = try std.fmt.allocPrint(allocator, "{s}\\command", .{item_path});
    defer allocator.free(command_path);
    try writeString(allocator, command_path, "DelegateExecute", extension_shared.clsid_string);
}

fn installClassRegistration(allocator: std.mem.Allocator, exe_path: []const u8) !void {
    const clsid_path = try std.fmt.allocPrint(allocator, "Software\\Classes\\CLSID\\{s}", .{extension_shared.clsid_string});
    defer allocator.free(clsid_path);
    try writeString(allocator, clsid_path, null, "Hasher ExecuteCommand");

    const local_server_path = try std.fmt.allocPrint(allocator, "{s}\\LocalServer32", .{clsid_path});
    defer allocator.free(local_server_path);
    const server_command = try localServerCommand(allocator, exe_path);
    defer allocator.free(server_command);
    try writeString(allocator, local_server_path, null, server_command);
}

fn registrationMatches(allocator: std.mem.Allocator, exe_path: []const u8) bool {
    for (registry_targets) |target| {
        if (!targetRegistrationMatches(allocator, target)) return false;
    }

    const clsid_path = std.fmt.allocPrint(allocator, "Software\\Classes\\CLSID\\{s}\\LocalServer32", .{extension_shared.clsid_string}) catch return false;
    defer allocator.free(clsid_path);
    const server_command = localServerCommand(allocator, exe_path) catch return false;
    defer allocator.free(server_command);
    return stringValueEquals(allocator, clsid_path, null, server_command);
}

fn targetRegistrationMatches(allocator: std.mem.Allocator, target: []const u8) bool {
    if (!hasStringValue(allocator, target, "SubCommands")) return false;
    for (extension_shared.menu_algorithms) |algorithm| {
        if (!menuRegistrationMatches(allocator, target, extension_shared.commandKey(algorithm))) return false;
    }
    return menuRegistrationMatches(allocator, target, "all");
}

fn menuRegistrationMatches(allocator: std.mem.Allocator, target: []const u8, key: []const u8) bool {
    const command_path = std.fmt.allocPrint(allocator, "{s}\\shell\\{s}\\command", .{ target, key }) catch return false;
    defer allocator.free(command_path);
    return stringValueEquals(allocator, command_path, "DelegateExecute", extension_shared.clsid_string);
}

fn localServerCommand(allocator: std.mem.Allocator, exe_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "\"{s}\"", .{exe_path});
}

fn deleteTree(allocator: std.mem.Allocator, path: []const u8) !void {
    const path_z = try std.unicode.utf8ToUtf16LeAllocZ(allocator, path);
    defer allocator.free(path_z);
    const result = RegDeleteTreeW(hkey_current_user, path_z.ptr);
    if (result != 0 and result != 2) return error.RegistryWriteFailed;
}

fn hasStringValue(allocator: std.mem.Allocator, path: []const u8, value_name: ?[]const u8) bool {
    const path_z = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return false;
    defer allocator.free(path_z);
    const name_z = if (value_name) |name| std.unicode.utf8ToUtf16LeAllocZ(allocator, name) catch return false else null;
    defer if (name_z) |name| allocator.free(name);
    var key: ?HKey = null;
    if (RegOpenKeyExW(hkey_current_user, path_z.ptr, 0, key_read, &key) != 0) return false;
    defer _ = RegCloseKey(key);
    var value_type: u32 = 0;
    var size: u32 = 0;
    return RegQueryValueExW(key, if (name_z) |name| name.ptr else null, null, &value_type, null, &size) == 0 and value_type == reg_sz;
}

fn stringValueEquals(allocator: std.mem.Allocator, path: []const u8, value_name: ?[]const u8, expected: []const u8) bool {
    const path_z = std.unicode.utf8ToUtf16LeAllocZ(allocator, path) catch return false;
    defer allocator.free(path_z);
    const name_z = if (value_name) |name| std.unicode.utf8ToUtf16LeAllocZ(allocator, name) catch return false else null;
    defer if (name_z) |name| allocator.free(name);
    const expected_z = std.unicode.utf8ToUtf16LeAllocZ(allocator, expected) catch return false;
    defer allocator.free(expected_z);

    var key: ?HKey = null;
    if (RegOpenKeyExW(hkey_current_user, path_z.ptr, 0, key_read, &key) != 0) return false;
    defer _ = RegCloseKey(key);
    var value_type: u32 = 0;
    var size: u32 = 0;
    const value_name_ptr = if (name_z) |name| name.ptr else null;
    if (RegQueryValueExW(key, value_name_ptr, null, &value_type, null, &size) != 0 or value_type != reg_sz) return false;
    const expected_size = @as(u32, @intCast((expected_z.len + 1) * @sizeOf(u16)));
    if (size != expected_size) return false;

    const data = allocator.alloc(u8, size) catch return false;
    defer allocator.free(data);
    if (RegQueryValueExW(key, value_name_ptr, null, &value_type, @ptrCast(data.ptr), &size) != 0) return false;
    const expected_bytes: [*]const u8 = @ptrCast(expected_z.ptr);
    return std.mem.eql(u8, data, expected_bytes[0..expected_size]);
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
    try std.testing.expectEqual(@as(usize, 1), request.paths.len);
    try std.testing.expectEqualStrings("C:\\file.txt", request.paths[0]);
}

test "parses the all-algorithms context-menu request" {
    const request = parseContextHashArgs(&.{ "hasher.exe", "--context-hash", "ALL", "C:\\file.txt" }).?;
    inline for (hash.all_algorithms) |algorithm| try std.testing.expect(request.options.enabled(algorithm));
}

test "parses multiple context-menu paths as one request" {
    const request = parseContextHashArgs(&.{
        "hasher.exe",
        "--context-hash",
        "SHA256",
        "C:\\first.txt",
        "C:\\second folder",
        "C:\\third",
    }).?;
    try std.testing.expectEqual(@as(usize, 3), request.paths.len);
    try std.testing.expectEqualStrings("C:\\first.txt", request.paths[0]);
    try std.testing.expectEqualStrings("C:\\second folder", request.paths[1]);
    try std.testing.expectEqualStrings("C:\\third", request.paths[2]);
}

test "context-menu command names match the COM command names" {
    try std.testing.expectEqualStrings("crc64-iso", extension_shared.commandKey(.crc64_iso));
    try std.testing.expectEqualStrings("sha256", extension_shared.commandKey(.sha256));
}

test "rejects incomplete context-menu requests" {
    try std.testing.expect(parseContextHashArgs(&.{ "hasher.exe", "--context-hash", "SHA256" }) == null);
}
