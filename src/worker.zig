const std = @import("std");
const files = @import("files.zig");
const hash = @import("hash/core.zig");

pub const Row = struct {
    file: files.FileEntry,
    result: hash.HashResult = .{},
    status: []u8,

    pub fn deinit(self: *Row, allocator: std.mem.Allocator) void {
        self.file.deinit(allocator);
        self.result.deinit(allocator);
        allocator.free(self.status);
    }
};

pub const AppState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mutex: std.atomic.Mutex = .unlocked,
    rows: std.ArrayList(Row),
    dropped_paths: std.ArrayList([]u8),
    options: hash.HashOptions = .{},
    uppercase: bool = true,
    processing: bool = false,
    progress_done: usize = 0,
    progress_total: usize = 0,
    status_message: []u8,
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    supervisor: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !AppState {
        return .{
            .allocator = allocator,
            .io = io,
            .rows = try std.ArrayList(Row).initCapacity(allocator, 0),
            .dropped_paths = try std.ArrayList([]u8).initCapacity(allocator, 0),
            .status_message = try allocator.dupe(u8, "就绪"),
        };
    }

    pub fn deinit(self: *AppState) void {
        self.stop();
        if (self.supervisor) |thread| thread.join();
        self.clearRowsLocked();
        self.rows.deinit(self.allocator);
        self.clearDroppedPathsLocked();
        self.dropped_paths.deinit(self.allocator);
        self.allocator.free(self.status_message);
    }

    pub fn setMessageLocked(self: *AppState, message: []const u8) void {
        self.allocator.free(self.status_message);
        self.status_message = self.allocator.dupe(u8, message) catch return;
    }

    pub fn clearRowsLocked(self: *AppState) void {
        for (self.rows.items) |*row| row.deinit(self.allocator);
        self.rows.clearRetainingCapacity();
        self.progress_done = 0;
        self.progress_total = 0;
    }

    pub fn clearDroppedPathsLocked(self: *AppState) void {
        for (self.dropped_paths.items) |path| self.allocator.free(path);
        self.dropped_paths.clearRetainingCapacity();
    }

    pub fn clear(self: *AppState) void {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        if (self.processing) {
            self.setMessageLocked("请先停止当前任务");
            return;
        }
        self.clearRowsLocked();
        self.clearDroppedPathsLocked();
        self.setMessageLocked("已清空");
    }

    pub fn stop(self: *AppState) void {
        self.stop_flag.store(true, .release);
    }

    pub fn addDroppedPaths(self: *AppState, paths: []const []const u8) void {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        if (self.processing) {
            self.setMessageLocked("请先停止当前任务");
            return;
        }
        self.clearDroppedPathsLocked();
        self.clearRowsLocked();
        for (paths) |path| {
            const copy = self.allocator.dupe(u8, path) catch continue;
            self.dropped_paths.append(self.allocator, copy) catch {
                self.allocator.free(copy);
                continue;
            };
            const name = self.allocator.dupe(u8, std.fs.path.basename(path)) catch continue;
            const size = self.allocator.dupe(u8, "等待中") catch {
                self.allocator.free(name);
                continue;
            };
            const status = self.allocator.dupe(u8, "排队中") catch {
                self.allocator.free(name);
                self.allocator.free(size);
                continue;
            };
            const row_path = self.allocator.dupe(u8, path) catch {
                self.allocator.free(name);
                self.allocator.free(size);
                self.allocator.free(status);
                continue;
            };
            self.rows.append(self.allocator, .{
                .file = .{ .path = row_path, .name = name, .size_label = size, .size_bytes = 0 },
                .status = status,
            }) catch {
                self.allocator.free(row_path);
                self.allocator.free(name);
                self.allocator.free(size);
                self.allocator.free(status);
            };
        }
        self.setMessageLocked("就绪");
    }

    pub fn start(self: *AppState) !void {
        lockMutex(&self.mutex);
        defer self.mutex.unlock();
        if (self.processing) return;
        if (!self.options.any()) {
            self.setMessageLocked("请至少选择一种算法");
            return;
        }
        if (self.dropped_paths.items.len == 0) {
            self.setMessageLocked("请拖入至少一个文件或文件夹");
            return;
        }
        if (self.supervisor) |thread| {
            thread.join();
            self.supervisor = null;
        }
        self.stop_flag.store(false, .release);
        self.processing = true;
        self.progress_done = 0;
        self.progress_total = 0;
        self.setMessageLocked("计算中");
        self.supervisor = try std.Thread.spawn(.{}, supervisorMain, .{self});
    }

};

const SharedJobs = struct {
    mutex: std.atomic.Mutex = .unlocked,
    next: usize = 0,
    entries: []files.FileEntry,
};

fn supervisorMain(state: *AppState) void {
    const allocator = state.allocator;
    var roots = std.ArrayList([]const u8).initCapacity(allocator, 0) catch return finishWithError(state, "内存不足");
    defer roots.deinit(allocator);

    lockMutex(&state.mutex);
    for (state.dropped_paths.items) |path| roots.append(allocator, path) catch {};
    const options = state.options;
    state.clearRowsLocked();
    state.mutex.unlock();

    var entries = files.collect(allocator, state.io, roots.items) catch return finishWithError(state, "收集文件失败");
    defer files.deinitEntries(&entries, allocator);

    lockMutex(&state.mutex);
    state.progress_total = entries.items.len;
    state.rows.ensureTotalCapacity(allocator, entries.items.len) catch {};
    for (entries.items) |entry| {
        state.rows.append(allocator, .{
            .file = .{
                .path = allocator.dupe(u8, entry.path) catch continue,
                .name = allocator.dupe(u8, entry.name) catch continue,
                .size_label = allocator.dupe(u8, entry.size_label) catch continue,
                .size_bytes = entry.size_bytes,
            },
            .status = allocator.dupe(u8, "排队中") catch continue,
        }) catch {};
    }
    state.mutex.unlock();

    var shared = SharedJobs{ .entries = entries.items };
    var threads: [4]std.Thread = undefined;
    var spawned: usize = 0;
    while (spawned < threads.len) : (spawned += 1) {
        threads[spawned] = std.Thread.spawn(.{}, workerMain, .{ state, &shared, options }) catch break;
    }
    for (threads[0..spawned]) |thread| thread.join();

    lockMutex(&state.mutex);
    state.processing = false;
    if (state.stop_flag.load(.acquire)) {
        state.setMessageLocked("已停止");
    } else {
        state.setMessageLocked("完成");
    }
    state.mutex.unlock();
}

fn workerMain(state: *AppState, shared: *SharedJobs, options: hash.HashOptions) void {
    while (!state.stop_flag.load(.acquire)) {
        const index = blk: {
            lockMutex(&shared.mutex);
            defer shared.mutex.unlock();
            if (shared.next >= shared.entries.len) return;
            const i = shared.next;
            shared.next += 1;
            break :blk i;
        };
        const path = shared.entries[index].path;
        var result = hash.calculateFile(state.allocator, state.io, path, options, &state.stop_flag) catch |err| {
            if (err == error.Stopped) return;
            lockMutex(&state.mutex);
            if (index < state.rows.items.len) {
                const message = std.fmt.allocPrint(state.allocator, "错误: {}", .{err}) catch {
                    state.mutex.unlock();
                    continue;
                };
                state.allocator.free(state.rows.items[index].status);
                state.rows.items[index].status = message;
                state.progress_done += 1;
            }
            state.mutex.unlock();
            continue;
        };

        lockMutex(&state.mutex);
        if (index < state.rows.items.len) {
            state.rows.items[index].result.deinit(state.allocator);
            state.rows.items[index].result = result;
            updateRowStatusLocked(state, index, "完成");
            state.progress_done += 1;
        } else {
            result.deinit(state.allocator);
        }
        state.mutex.unlock();
    }
}

fn updateRowStatusLocked(state: *AppState, index: usize, message: []const u8) void {
    const status = state.allocator.dupe(u8, message) catch return;
    state.allocator.free(state.rows.items[index].status);
    state.rows.items[index].status = status;
}

fn finishWithError(state: *AppState, message: []const u8) void {
    lockMutex(&state.mutex);
    defer state.mutex.unlock();
    state.processing = false;
    state.setMessageLocked(message);
}

pub fn lockMutex(mutex: *std.atomic.Mutex) void {
    while (!mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}
