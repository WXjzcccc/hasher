const std = @import("std");
const builtin = @import("builtin");

const context_menu = @import("context_menu.zig");
const hash = @import("hash/core.zig");
const worker = @import("worker.zig");
const windows_frame = @import("windows_frame.zig");

extern "kernel32" fn CreateMutexW(
    security_attributes: ?*const anyopaque,
    initial_owner: bool,
    name: [*:0]const u16,
) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetLastError() callconv(.winapi) u32;
extern "kernel32" fn CloseHandle(handle: ?*anyopaque) callconv(.winapi) bool;
extern "kernel32" fn Sleep(milliseconds: u32) callconv(.winapi) void;
extern "user32" fn FindWindowW(class_name: ?[*:0]const u16, window_name: ?[*:0]const u16) callconv(.winapi) ?*anyopaque;
extern "user32" fn SendMessageW(hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize;

const error_already_exists: u32 = 183;
const mutex_name = std.unicode.utf8ToUtf16LeStringLiteral("Local\\Hasher.SingleInstance");
const window_title_u16 = std.unicode.utf8ToUtf16LeStringLiteral("Hasher 1.5");

pub const window_title = "Hasher 1.5";
pub const context_payload_magic = "HSR1";

pub const RequestQueue = struct {
    allocator: std.mem.Allocator,
    paths: std.ArrayList([]u8),
    options: hash.HashOptions = hash.HashOptions.none(),
    deadline: f64 = 0,

    pub fn init(allocator: std.mem.Allocator) RequestQueue {
        return .{ .allocator = allocator, .paths = std.ArrayList([]u8).empty };
    }

    pub fn deinit(self: *RequestQueue) void {
        self.clear();
        self.paths.deinit(self.allocator);
    }

    pub fn enqueueRequest(self: *RequestQueue, request: context_menu.ContextHashRequest) void {
        for (request.paths) |path| self.enqueuePath(request.options, path);
        self.deadline = 0;
    }

    pub fn receivePayload(self: *RequestQueue, data: []const u8) void {
        if (data.len < context_payload_magic.len + 1 or !std.mem.eql(u8, data[0..context_payload_magic.len], context_payload_magic)) return;
        const options = context_menu.optionsFromMask(data[context_payload_magic.len]);
        var cursor = context_payload_magic.len + 1;
        while (cursor < data.len) {
            const end = std.mem.indexOfScalar(u8, data[cursor..], 0) orelse return;
            self.enqueuePath(options, data[cursor .. cursor + end]);
            cursor += end + 1;
        }
        self.deadline = 0;
    }

    pub fn startIfReady(self: *RequestQueue, app: *worker.AppState, now: f64) void {
        if (self.paths.items.len == 0) return;
        if (self.deadline == 0) {
            self.deadline = now + 0.16;
            return;
        }
        if (now < self.deadline) return;

        worker.lockMutex(&app.mutex);
        const processing = app.processing;
        if (!processing) app.options = self.options;
        app.mutex.unlock();
        if (processing) {
            self.deadline = now + 0.1;
            return;
        }

        app.addDroppedPaths(self.paths.items);
        self.clear();
        app.start() catch {};
    }

    fn enqueuePath(self: *RequestQueue, options: hash.HashOptions, path: []const u8) void {
        if (path.len == 0) return;
        if (self.paths.items.len == 0) {
            self.options = options;
        } else if (context_menu.optionsMask(self.options) != context_menu.optionsMask(options)) {
            self.clear();
            self.options = options;
        }
        for (self.paths.items) |existing| {
            if (std.mem.eql(u8, existing, path)) return;
        }
        const copy = self.allocator.dupe(u8, path) catch return;
        self.paths.append(self.allocator, copy) catch {
            self.allocator.free(copy);
            return;
        };
        self.deadline = 0;
    }

    fn clear(self: *RequestQueue) void {
        for (self.paths.items) |path| self.allocator.free(path);
        self.paths.clearRetainingCapacity();
        self.deadline = 0;
    }
};

pub fn handleCopyData(context: ?*anyopaque, data: []const u8) void {
    const queue: *RequestQueue = @ptrCast(@alignCast(context orelse return));
    queue.receivePayload(data);
}

pub const Instance = struct {
    mutex: ?*anyopaque = null,
    forwarded: bool = false,

    pub fn deinit(self: *Instance) void {
        if (self.mutex) |mutex| _ = CloseHandle(mutex);
        self.mutex = null;
    }
};

pub fn acquireOrForward(allocator: std.mem.Allocator, request: ?context_menu.ContextHashRequest) !Instance {
    if (builtin.os.tag != .windows) return .{};

    const mutex = CreateMutexW(null, true, mutex_name.ptr) orelse return error.SingleInstanceMutexFailed;
    if (GetLastError() != error_already_exists) return .{ .mutex = mutex };

    if (request) |value| {
        const sent = sendRequest(allocator, value) catch |err| {
            _ = CloseHandle(mutex);
            return err;
        };
        _ = CloseHandle(mutex);
        if (sent) return .{ .forwarded = true };
        return error.ExistingInstanceUnavailable;
    }

    _ = CloseHandle(mutex);
    return .{};
}

fn sendRequest(allocator: std.mem.Allocator, request: context_menu.ContextHashRequest) !bool {
    var payload = try encodeContextRequest(allocator, request);
    defer payload.deinit(allocator);
    if (payload.items.len == 0) return false;

    const copy_data = extern struct {
        dw_data: usize,
        cb_data: u32,
        lp_data: ?*const anyopaque,
    }{
        .dw_data = windows_frame.copy_data_id,
        .cb_data = @intCast(payload.items.len),
        .lp_data = payload.items.ptr,
    };

    // The first process may still be creating its window and installing the message handler.
    for (0..500) |_| {
        if (FindWindowW(null, window_title_u16.ptr)) |hwnd| {
            const result = SendMessageW(
                hwnd,
                windows_frame.wm_copydata,
                0,
                @as(isize, @bitCast(@intFromPtr(&copy_data))),
            );
            if (result != 0) return true;
        }
        Sleep(10);
    }
    return false;
}

pub fn encodeContextRequest(allocator: std.mem.Allocator, request: context_menu.ContextHashRequest) !std.ArrayList(u8) {
    var payload = std.ArrayList(u8).empty;
    errdefer payload.deinit(allocator);
    try payload.appendSlice(allocator, context_payload_magic);
    try payload.append(allocator, context_menu.optionsMask(request.options));
    for (request.paths) |path| {
        if (path.len == 0) continue;
        try payload.appendSlice(allocator, path);
        try payload.append(allocator, 0);
    }
    return payload;
}
