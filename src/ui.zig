const std = @import("std");
const zgui = @import("zgui");
const zglfw = @import("zglfw");

const hash = @import("hash/core.zig");
const worker = @import("worker.zig");

const GL_COLOR_BUFFER_BIT: c_uint = 0x00004000;

extern "opengl32" fn glViewport(x: c_int, y: c_int, width: c_int, height: c_int) callconv(.c) void;
extern "opengl32" fn glClearColor(red: f32, green: f32, blue: f32, alpha: f32) callconv(.c) void;
extern "opengl32" fn glClear(mask: c_uint) callconv(.c) void;

const cjk_ranges = [_:0]zgui.Wchar{
    0x0020, 0x00ff,
    0x2000, 0x206f,
    0x3000, 0x30ff,
    0x31f0, 0x31ff,
    0x4e00, 0x9fff,
    0xff00, 0xffef,
    0,
};

const FilterColumn = enum(i32) {
    all,
    file,
    size,
    md5,
    sha1,
    sha256,
    sha512,
    sm3,
    crc32,
    crc64_iso,
    crc64_ecma,
    path,
};

const filter_items = "全部\x00文件\x00大小\x00MD5\x00SHA1\x00SHA256\x00SHA512\x00SM3\x00CRC32\x00CRC64_ISO\x00CRC64_ECMA\x00完整路径\x00";
const algorithm_labels_z = [_][:0]const u8{
    "MD5", "SHA1", "SHA256", "SHA512", "SM3", "CRC32", "CRC64_ISO", "CRC64_ECMA",
};

const UiState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    app: worker.AppState,
    window: *zglfw.Window,
    font_bytes: ?[]u8 = null,
    dpi_scale: f32 = 1.0,
    applied_style_scale: f32 = 0,
    filter_column: i32 = @intFromEnum(FilterColumn.all),
    search_buf: [512:0]u8 = @splat(0),
    dragging_title: bool = false,
    drag_mouse_start: [2]f64 = .{ 0, 0 },
    drag_window_start: [2]c_int = .{ 0, 0 },

    fn init(allocator: std.mem.Allocator, io: std.Io, window: *zglfw.Window) !UiState {
        return .{
            .allocator = allocator,
            .io = io,
            .window = window,
            .app = try worker.AppState.init(allocator, io),
        };
    }

    fn deinit(self: *UiState) void {
        self.app.deinit();
        if (self.font_bytes) |bytes| self.allocator.free(bytes);
    }
};

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    enableDpiAwareness();

    try zglfw.init();
    defer zglfw.terminate();

    zglfw.windowHint(.context_version_major, 3);
    zglfw.windowHint(.context_version_minor, 3);
    zglfw.windowHint(.opengl_profile, .opengl_core_profile);
    zglfw.windowHint(.decorated, false);
    zglfw.windowHint(.resizable, true);
    zglfw.windowHint(.scale_to_monitor, true);
    zglfw.windowHint(.scale_framebuffer, true);

    const window = try zglfw.Window.create(1180, 760, "Hasher", null, null);
    defer window.destroy();
    window.setSizeLimits(820, 520, -1, -1);
    zglfw.makeContextCurrent(window);
    zglfw.swapInterval(1);

    zgui.init(allocator);
    defer zgui.deinit();
    zgui.io.setIniFilename(null);
    zgui.backend.init(window);
    defer zgui.backend.deinit();

    var ui = try UiState.init(allocator, io, window);
    defer ui.deinit();
    updateScale(&ui);
    applyScaledStyle(&ui);
    try reloadFont(&ui);

    _ = window.setDropCallback(dropCallback);
    window.setUserPointer(&ui);

    while (!window.shouldClose()) {
        zglfw.pollEvents();
        updateScale(&ui);

        const win_size = window.getSize();
        const fb_size = window.getFramebufferSize();
        zgui.backend.newFrame(@intCast(@max(win_size[0], 1)), @intCast(@max(win_size[1], 1)));
        zgui.io.setDisplaySize(@floatFromInt(@max(win_size[0], 1)), @floatFromInt(@max(win_size[1], 1)));
        zgui.io.setDisplayFramebufferScale(
            @as(f32, @floatFromInt(@max(fb_size[0], 1))) / @as(f32, @floatFromInt(@max(win_size[0], 1))),
            @as(f32, @floatFromInt(@max(fb_size[1], 1))) / @as(f32, @floatFromInt(@max(win_size[1], 1))),
        );

        drawFrame(&ui, @floatFromInt(win_size[0]), @floatFromInt(win_size[1]));

        glViewport(0, 0, @intCast(@max(fb_size[0], 1)), @intCast(@max(fb_size[1], 1)));
        glClearColor(0.09, 0.10, 0.12, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        zgui.backend.draw();
        window.swapBuffers();
    }
}

fn enableDpiAwareness() void {
    if (@import("builtin").os.tag != .windows) return;
    const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: isize = -4;
    _ = SetProcessDpiAwarenessContext(@ptrFromInt(@as(usize, @bitCast(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2))));
}

extern "user32" fn SetProcessDpiAwarenessContext(value: ?*anyopaque) callconv(.winapi) bool;

fn loadFontBytes(ui: *UiState) ![]u8 {
    const candidates = [_][]const u8{
        "assets/shousha.ttf",
        "C:\\Windows\\Fonts\\msyh.ttc",
        "C:\\Windows\\Fonts\\simhei.ttf",
        "C:\\Windows\\Fonts\\simsun.ttc",
    };
    for (candidates) |path| {
        return std.Io.Dir.cwd().readFileAlloc(ui.io, path, ui.allocator, .limited(96 * 1024 * 1024)) catch continue;
    }
    return error.FontNotFound;
}

fn reloadFont(ui: *UiState) !void {
    if (ui.font_bytes == null) ui.font_bytes = try loadFontBytes(ui);
    var cfg = zgui.FontConfig.init();
    cfg.oversample_h = 2;
    cfg.oversample_v = 2;
    cfg.rasterizer_density = ui.dpi_scale;
    const font = zgui.io.addFontFromMemoryWithConfig(ui.font_bytes.?, scale(ui, 16.0), cfg, &cjk_ranges);
    zgui.io.setDefaultFont(font);
}

fn updateScale(ui: *UiState) void {
    const content_scale = ui.window.getContentScale();
    const next = @max(content_scale[0], content_scale[1]);
    ui.dpi_scale = if (next <= 0) 1.0 else next;
    if (@abs(ui.dpi_scale - ui.applied_style_scale) > 0.01) applyScaledStyle(ui);
}

fn applyScaledStyle(ui: *UiState) void {
    const style = zgui.getStyle();
    style.* = zgui.Style.init();
    zgui.styleColorsDark(style);
    style.window_rounding = 0;
    style.window_border_size = 0;
    style.frame_rounding = scale(ui, 3);
    style.frame_padding = .{ scale(ui, 8), scale(ui, 4) };
    style.item_spacing = .{ scale(ui, 8), scale(ui, 5) };
    style.cell_padding = .{ scale(ui, 5), scale(ui, 3) };
    style.scrollbar_size = scale(ui, 13);
    ui.applied_style_scale = ui.dpi_scale;
}

fn scale(ui: *const UiState, value: f32) f32 {
    return value * ui.dpi_scale;
}

fn dropCallback(window: *zglfw.Window, path_count: i32, paths: [*][*:0]const u8) callconv(.c) void {
    const ui = window.getUserPointer(UiState) orelse return;
    const count: usize = @intCast(@max(path_count, 0));
    var list: [64][]const u8 = undefined;
    const n = @min(count, list.len);
    for (0..n) |i| list[i] = std.mem.span(paths[i]);
    ui.app.addDroppedPaths(list[0..n]);
}

fn drawFrame(ui: *UiState, width: f32, height: f32) void {
    zgui.setNextWindowPos(.{ .x = 0, .y = 0 });
    zgui.setNextWindowSize(.{ .w = width, .h = height });
    const flags = zgui.WindowFlags{
        .no_title_bar = true,
        .no_resize = true,
        .no_move = true,
        .no_scrollbar = true,
        .no_collapse = true,
        .no_saved_settings = true,
    };
    if (zgui.begin("HasherRoot", .{ .flags = flags })) {
        drawTitleBar(ui, width);
        zgui.separator();
        drawToolbar(ui);
        drawOptions(ui);
        drawStatus(ui);
        drawTable(ui);
    }
    zgui.end();
}

fn drawTitleBar(ui: *UiState, width: f32) void {
    const title_h = scale(ui, 32);
    zgui.pushStyleVar2f(.{ .idx = .frame_padding, .v = .{ scale(ui, 8), scale(ui, 3) } });
    defer zgui.popStyleVar(.{});

    zgui.text("Hasher", .{});
    zgui.sameLine(.{ .offset_from_start_x = width - scale(ui, 118) });
    if (zgui.smallButton("_")) ui.window.iconify();
    zgui.sameLine(.{});
    if (zgui.smallButton(if (ui.window.getAttribute(.maximized)) "[]" else "[ ]")) {
        if (ui.window.getAttribute(.maximized)) ui.window.restore() else ui.window.maximize();
    }
    zgui.sameLine(.{});
    zgui.pushStyleColor4f(.{ .idx = .button, .c = .{ 0.72, 0.16, 0.18, 1.0 } });
    zgui.pushStyleColor4f(.{ .idx = .button_hovered, .c = .{ 0.95, 0.22, 0.24, 1.0 } });
    if (zgui.smallButton("X")) ui.window.setShouldClose(true);
    zgui.popStyleColor(.{ .count = 2 });

    zgui.setCursorPos(.{ 0, 0 });
    _ = zgui.invisibleButton("title_drag", .{ .w = width - scale(ui, 130), .h = title_h });
    handleTitleDrag(ui);
}

fn handleTitleDrag(ui: *UiState) void {
    if (zgui.isItemActive() and zgui.isMouseDown(.left)) {
        const mouse = ui.window.getCursorPos();
        if (!ui.dragging_title) {
            ui.dragging_title = true;
            ui.drag_mouse_start = mouse;
            ui.drag_window_start = ui.window.getPos();
        }
        const dx: c_int = @intFromFloat(mouse[0] - ui.drag_mouse_start[0]);
        const dy: c_int = @intFromFloat(mouse[1] - ui.drag_mouse_start[1]);
        ui.window.setPos(ui.drag_window_start[0] + dx, ui.drag_window_start[1] + dy);
    } else {
        ui.dragging_title = false;
    }
}

fn drawToolbar(ui: *UiState) void {
    if (zgui.button("开始", .{})) ui.app.start() catch {};
    zgui.sameLine(.{});
    if (zgui.button("停止", .{})) ui.app.stop();
    zgui.sameLine(.{});
    if (zgui.button("清空", .{})) ui.app.clear();
    zgui.sameLine(.{});
    if (zgui.button("复制", .{})) copyRows(ui, true) catch {};
    zgui.sameLine(.{});
    if (zgui.button("复制无路径", .{})) copyRows(ui, false) catch {};
    zgui.sameLine(.{ .spacing = scale(ui, 18) });
    zgui.setNextItemWidth(scale(ui, 122));
    _ = zgui.combo("##filter", .{ .current_item = &ui.filter_column, .items_separated_by_zeros = filter_items });
    zgui.sameLine(.{});
    zgui.setNextItemWidth(scale(ui, 260));
    _ = zgui.inputTextWithHint("##search", .{ .hint = "搜索", .buf = ui.search_buf[0..511 :0] });
    zgui.sameLine(.{});
    if (zgui.button("重置", .{})) @memset(&ui.search_buf, 0);
}

fn drawOptions(ui: *UiState) void {
    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();
    for (hash.all_algorithms) |algorithm| {
        var enabled = ui.app.options.enabled(algorithm);
        if (zgui.checkbox(algorithmLabelZ(algorithm), .{ .v = &enabled })) ui.app.options.set(algorithm, enabled);
        zgui.sameLine(.{});
    }
    _ = zgui.checkbox("大写", .{ .v = &ui.app.uppercase });
}

fn drawStatus(ui: *UiState) void {
    worker.lockMutex(&ui.app.mutex);
    const done = ui.app.progress_done;
    const total = ui.app.progress_total;
    const processing = ui.app.processing;
    const status = ui.app.status_message;
    ui.app.mutex.unlock();

    const percent: f32 = if (total == 0) 0 else @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(total));
    zgui.progressBar(.{ .fraction = percent, .w = -1, .h = scale(ui, 18) });
    zgui.text("{s} {d}/{d}{s}", .{ status, done, total, if (processing) " ..." else "" });
}

fn drawTable(ui: *UiState) void {
    const flags = zgui.TableFlags{
        .resizable = true,
        .row_bg = true,
        .borders = .{ .inner_v = true, .outer_v = true, .inner_h = true, .outer_h = true },
        .scroll_x = true,
        .scroll_y = true,
        .sizing = .fixed_fit,
    };
    if (!zgui.beginTable("results", .{ .column = 12, .flags = flags, .outer_size = .{ 0, -1 } })) return;
    defer zgui.endTable();
    setupColumn(ui, "文件", 170);
    setupColumn(ui, "大小", 150);
    for (hash.all_algorithms) |algorithm| setupColumn(ui, algorithmLabelZ(algorithm), 165);
    setupColumn(ui, "状态", 100);
    setupColumn(ui, "完整路径", 360);
    zgui.tableSetupScrollFreeze(0, 1);
    zgui.tableHeadersRow();

    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();
    for (ui.app.rows.items) |row| {
        if (!rowMatches(ui, row)) continue;
        zgui.tableNextRow(.{});
        tableText(row.file.name);
        tableText(row.file.size_label);
        for (hash.all_algorithms) |algorithm| tableHash(ui, row.result.get(algorithm));
        tableText(row.status);
        tableText(row.file.path);
    }
}

fn setupColumn(ui: *const UiState, label: [:0]const u8, width: f32) void {
    zgui.tableSetupColumn(label, .{ .flags = .{ .width_fixed = true }, .init_width_or_height = scale(ui, width) });
}

fn tableText(text: []const u8) void {
    _ = zgui.tableNextColumn();
    zgui.text("{s}", .{text});
}

fn tableHash(ui: *UiState, text: []const u8) void {
    _ = zgui.tableNextColumn();
    if (!ui.app.uppercase) {
        zgui.text("{s}", .{text});
        return;
    }
    var buf: [128]u8 = undefined;
    zgui.text("{s}", .{uppercaseInto(&buf, text)});
}

fn rowMatches(ui: *UiState, row: worker.Row) bool {
    const needle = std.mem.sliceTo(&ui.search_buf, 0);
    if (needle.len == 0) return true;
    const col: FilterColumn = @enumFromInt(std.math.clamp(ui.filter_column, 0, @intFromEnum(FilterColumn.path)));
    return switch (col) {
        .all => contains(row.file.name, needle) or contains(row.file.size_label, needle) or contains(row.file.path, needle) or resultContains(row.result, needle),
        .file => contains(row.file.name, needle),
        .size => contains(row.file.size_label, needle),
        .path => contains(row.file.path, needle),
        .md5, .sha1, .sha256, .sha512, .sm3, .crc32, .crc64_iso, .crc64_ecma => contains(row.result.get(algorithmFromColumn(col)), needle),
    };
}

fn resultContains(result: hash.HashResult, needle: []const u8) bool {
    for (hash.all_algorithms) |algorithm| {
        if (contains(result.get(algorithm), needle)) return true;
    }
    return false;
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.ascii.indexOfIgnoreCase(haystack, needle) != null;
}

fn algorithmFromColumn(column: FilterColumn) hash.Algorithm {
    return switch (column) {
        .md5 => .md5,
        .sha1 => .sha1,
        .sha256 => .sha256,
        .sha512 => .sha512,
        .sm3 => .sm3,
        .crc32 => .crc32,
        .crc64_iso => .crc64_iso,
        .crc64_ecma => .crc64_ecma,
        else => .sha256,
    };
}

fn copyRows(ui: *UiState, include_path: bool) !void {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(ui.allocator);
    try out.appendSlice(ui.allocator, "文件\t大小");
    for (hash.all_algorithms) |algorithm| try out.print(ui.allocator, "\t{s}", .{algorithm.label()});
    if (include_path) try out.appendSlice(ui.allocator, "\t完整路径");
    try out.append(ui.allocator, '\n');

    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();
    for (ui.app.rows.items) |row| {
        if (!rowMatches(ui, row)) continue;
        try out.print(ui.allocator, "{s}\t{s}", .{ row.file.name, row.file.size_label });
        for (hash.all_algorithms) |algorithm| {
            const value = row.result.get(algorithm);
            if (ui.app.uppercase) {
                var buf: [128]u8 = undefined;
                try out.print(ui.allocator, "\t{s}", .{uppercaseInto(&buf, value)});
            } else {
                try out.print(ui.allocator, "\t{s}", .{value});
            }
        }
        if (include_path) try out.print(ui.allocator, "\t{s}", .{row.file.path});
        try out.append(ui.allocator, '\n');
    }
    const z = try ui.allocator.dupeZ(u8, out.items);
    defer ui.allocator.free(z);
    zgui.setClipboardText(z);
}

fn uppercaseInto(buf: []u8, value: []const u8) []const u8 {
    const len = @min(buf.len, value.len);
    for (value[0..len], 0..) |ch, i| buf[i] = std.ascii.toUpper(ch);
    return buf[0..len];
}

fn algorithmLabelZ(algorithm: hash.Algorithm) [:0]const u8 {
    return algorithm_labels_z[@intFromEnum(algorithm)];
}
