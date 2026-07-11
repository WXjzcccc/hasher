const std = @import("std");
const rl = @import("raylib");

const hash = @import("hash/core.zig");
const worker = @import("worker.zig");
const font_atlas = @import("font_atlas.zig");
const embedded_assets = @import("embedded_assets");
const context_menu = @import("context_menu.zig");
const windows_frame = @import("windows_frame.zig");

extern "comdlg32" fn GetSaveFileNameW(ofn: *OpenFileNameW) callconv(.winapi) bool;

const OpenFileNameW = extern struct {
    lStructSize: u32,
    hwndOwner: ?*anyopaque = null,
    hInstance: ?*anyopaque = null,
    lpstrFilter: ?[*:0]const u16 = null,
    lpstrCustomFilter: ?[*:0]u16 = null,
    nMaxCustFilter: u32 = 0,
    nFilterIndex: u32 = 1,
    lpstrFile: [*:0]u16,
    nMaxFile: u32,
    lpstrFileTitle: ?[*:0]u16 = null,
    nMaxFileTitle: u32 = 0,
    lpstrInitialDir: ?[*:0]const u16 = null,
    lpstrTitle: ?[*:0]const u16 = null,
    Flags: u32,
    nFileOffset: u16 = 0,
    nFileExtension: u16 = 0,
    lpstrDefExt: ?[*:0]const u16 = null,
    lCustData: isize = 0,
    lpfnHook: ?*anyopaque = null,
    lpTemplateName: ?[*:0]const u16 = null,
    pvReserved: ?*anyopaque = null,
    dwReserved: u32 = 0,
    FlagsEx: u32 = 0,
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

const filter_labels = [_][]const u8{
    "全部",
    "文件",
    "大小",
    "MD5",
    "SHA1",
    "SHA256",
    "SHA512",
    "SM3",
    "CRC32",
    "CRC64_ISO",
    "CRC64_ECMA",
    "完整路径",
};
const algorithm_labels_z = [_][:0]const u8{
    "MD5", "SHA1", "SHA256", "SHA512", "SM3", "CRC32", "CRC64_ISO", "CRC64_ECMA",
};

const Color = rl.Color;
const Vec2 = rl.Vector2;
const Rect = rl.Rectangle;
const logical_font_size: f32 = 16;

const colors = struct {
    const bg = Color.init(14, 17, 19, 255);
    const panel = Color.init(22, 27, 32, 255);
    const panel2 = Color.init(29, 35, 42, 255);
    const border = Color.init(61, 68, 78, 255);
    const text = Color.init(232, 237, 244, 255);
    const muted = Color.init(145, 154, 166, 255);
    const button = Color.init(32, 57, 86, 255);
    const button_hover = Color.init(45, 77, 115, 255);
    const button_down = Color.init(56, 95, 139, 255);
    const button_disabled = Color.init(25, 31, 37, 255);
    const accent = Color.init(74, 153, 225, 255);
    const accent_hover = Color.init(91, 170, 239, 255);
    const danger = Color.init(180, 48, 57, 255);
    const close_hover = Color.init(232, 17, 35, 255);
    const close_down = Color.init(196, 13, 29, 255);
    const hash_value = Color.init(104, 211, 227, 255);
    const success = Color.init(93, 201, 128, 255);
    const warning = Color.init(235, 184, 82, 255);
    const path = Color.init(174, 183, 196, 255);
    const row_alt = Color.init(18, 22, 26, 255);
    const row_hover = Color.init(27, 36, 45, 255);
    const selected = Color.init(45, 91, 130, 255);
    const input = Color.init(20, 25, 31, 255);
    const scrollbar_track = Color.init(18, 23, 28, 255);
    const scrollbar_thumb = Color.init(82, 94, 108, 255);
};

const ButtonVisual = struct {
    clicked: bool,
    hovered: bool,
    pressed: bool,
};

const Icon = enum {
    minimize,
    maximize,
    restore,
    close,
    check,
    play,
    stop,
    clear,
    copy,
    copy_no_path,
    save,
    save_no_path,
    reset,
    chevron_down,
    settings,
};

const FlowLayout = struct {
    x: f32,
    y: f32,
    start_x: f32,
    max_x: f32,
    item_height: f32,
    gap: f32,
    row_gap: f32,

    fn init(start_x: f32, start_y: f32, max_x: f32, item_height: f32, gap: f32, row_gap: f32) FlowLayout {
        return .{ .x = start_x, .y = start_y, .start_x = start_x, .max_x = max_x, .item_height = item_height, .gap = gap, .row_gap = row_gap };
    }

    fn next(self: *FlowLayout, width: f32) Rect {
        if (self.x > self.start_x and self.x + width > self.max_x) {
            self.x = self.start_x;
            self.y += self.item_height + self.row_gap;
        }
        const result = rect(self.x, self.y, @min(width, self.max_x - self.start_x), self.item_height);
        self.x += result.width + self.gap;
        return result;
    }

    fn bottom(self: *const FlowLayout) f32 {
        return self.y + self.item_height;
    }
};

const UiState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    app: worker.AppState,
    font: rl.Font = undefined,
    font_loaded: bool = false,
    font_codepoints: []i32 = &.{},
    font_render_scale: f32 = 0,
    font_text_hash: u64 = 0,
    font_revision: u64 = 0,
    drawn_codepoints: std.AutoHashMap(i32, void),
    app_icon: rl.Texture2D = undefined,
    app_icon_loaded: bool = false,
    render_scale: f32 = 1.0,
    filter_column: i32 = @intFromEnum(FilterColumn.all),
    filter_open: bool = false,
    filter_button_rect: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    search_buf: [512:0]u8 = @splat(0),
    search_len: usize = 0,
    search_active: bool = false,
    dragging_title: bool = false,
    drag_mouse_start: Vec2 = .{ .x = 0, .y = 0 },
    drag_window_start: Vec2 = .{ .x = 0, .y = 0 },
    table_scroll_y: f32 = 0,
    table_scroll_x: f32 = 0,
    dragging_hscroll: bool = false,
    dragging_vscroll: bool = false,
    hscroll_grab_offset: f32 = 0,
    vscroll_grab_offset: f32 = 0,
    column_widths: [12]f32 = defaultColumnWidths(),
    resizing_column: ?usize = null,
    selected_row: ?usize = null,
    selected_column: ?usize = null,
    rounded_frame_width: i32 = 0,
    rounded_frame_height: i32 = 0,
    rounded_frame_maximized: bool = false,
    context_menu_enabled: bool = false,
    current_cursor: rl.MouseCursor = .default,
    requested_cursor: rl.MouseCursor = .default,

    fn init(allocator: std.mem.Allocator, io: std.Io) !UiState {
        return .{
            .allocator = allocator,
            .io = io,
            .app = try worker.AppState.init(allocator, io),
            .drawn_codepoints = std.AutoHashMap(i32, void).init(allocator),
        };
    }

    fn deinit(self: *UiState) void {
        if (self.app_icon_loaded) rl.unloadTexture(self.app_icon);
        if (self.font_loaded) rl.unloadFont(self.font);
        self.allocator.free(self.font_codepoints);
        self.drawn_codepoints.deinit();
        self.app.deinit();
    }
};

fn defaultColumnWidths() [12]f32 {
    return .{ 180, 126, 170, 170, 170, 170, 170, 170, 170, 170, 92, 380 };
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, context_request: ?context_menu.ContextHashRequest) !void {
    rl.setConfigFlags(.{
        .window_resizable = true,
        .window_undecorated = true,
        .window_highdpi = true,
        .msaa_4x_hint = true,
        .vsync_hint = true,
    });
    rl.initWindow(1180, 760, "Hasher 1.4");
    defer rl.closeWindow();
    windows_frame.installNativeFrame(rl.getWindowHandle());
    setAppIcon();
    rl.setExitKey(.null);
    rl.setTargetFPS(60);

    var ui = try UiState.init(allocator, io);
    defer ui.deinit();
    ui.context_menu_enabled = context_menu.isInstalled(allocator);
    if (ui.context_menu_enabled) context_menu.install(allocator) catch {};
    updateScale(&ui);
    updateWindowFrame(&ui);
    loadAppIconTexture(&ui);
    try loadFont(&ui);
    rl.setWindowMinSize(820, 520);
    if (context_request) |request| startContextHash(&ui, request);

    while (!rl.windowShouldClose()) {
        beginCursorFrame(&ui);
        updateScale(&ui);
        updateWindowFrame(&ui);
        handleDrops(&ui);
        handleSearchInput(&ui);
        handleWindowResize(&ui);
        handleWindowDrag(&ui);
        try ensureFontCurrent(&ui);

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(colors.bg);
        drawFrame(&ui);
        finishCursorFrame(&ui);
    }
}

fn beginCursorFrame(ui: *UiState) void {
    ui.requested_cursor = .default;
}

fn requestCursor(ui: *UiState, cursor: rl.MouseCursor) void {
    ui.requested_cursor = cursor;
}

fn finishCursorFrame(ui: *UiState) void {
    if (ui.current_cursor == ui.requested_cursor) return;
    rl.setMouseCursor(ui.requested_cursor);
    ui.current_cursor = ui.requested_cursor;
}

fn updateWindowFrame(ui: *UiState) void {
    const width = rl.getRenderWidth();
    const height = rl.getRenderHeight();
    const maximized = rl.isWindowMaximized();
    if (width == ui.rounded_frame_width and height == ui.rounded_frame_height and maximized == ui.rounded_frame_maximized) return;
    windows_frame.updateRoundedFrame(rl.getWindowHandle(), width, height, maximized);
    ui.rounded_frame_width = width;
    ui.rounded_frame_height = height;
    ui.rounded_frame_maximized = maximized;
}

fn startContextHash(ui: *UiState, request: context_menu.ContextHashRequest) void {
    worker.lockMutex(&ui.app.mutex);
    ui.app.options = request.options;
    ui.app.mutex.unlock();
    ui.app.addDroppedPaths(&.{request.path});
    ui.app.start() catch {};
}

fn setAppIcon() void {
    const icon = rl.loadImageFromMemory(".png", embedded_assets.icon_png) catch return;
    defer rl.unloadImage(icon);
    rl.setWindowIcon(icon);
}

fn loadAppIconTexture(ui: *UiState) void {
    const image = rl.loadImageFromMemory(".png", embedded_assets.icon_png) catch return;
    defer rl.unloadImage(image);
    const texture = rl.loadTextureFromImage(image) catch return;
    if (!rl.isTextureValid(texture)) return;
    ui.app_icon = texture;
    rl.genTextureMipmaps(&ui.app_icon);
    rl.setTextureFilter(ui.app_icon, .trilinear);
    ui.app_icon_loaded = true;
}

fn updateScale(ui: *UiState) void {
    const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
    const render_w: f32 = @floatFromInt(rl.getRenderWidth());
    ui.render_scale = if (screen_w > 0) @max(1.0, render_w / screen_w) else 1.0;
}

fn scale(ui: *const UiState, value: f32) f32 {
    _ = ui;
    return value;
}

fn pixelScale(ui: *const UiState, value: f32) f32 {
    return value * ui.render_scale;
}

fn snapToPhysicalPixel(ui: *const UiState, value: f32) f32 {
    if (ui.render_scale <= 0) return value;
    return @round(value * ui.render_scale) / ui.render_scale;
}

fn beginScissor(ui: *const UiState, r: Rect) void {
    _ = ui;
    rl.beginScissorMode(@intFromFloat(r.x), @intFromFloat(r.y), @intFromFloat(r.width), @intFromFloat(r.height));
}

fn loadFont(ui: *UiState) !void {
    ui.font_text_hash = computeFontTextHash(ui);
    ui.font_codepoints = try buildFontCodepoints(ui);
    ui.font = loadFontAtlas(ui, ui.font_codepoints) catch {
        ui.font = try rl.getFontDefault();
        ui.font_render_scale = ui.render_scale;
        return;
    };
    ui.font_loaded = true;
    ui.font_render_scale = ui.render_scale;
}

fn ensureFontCurrent(ui: *UiState) !void {
    const current_hash = computeFontTextHash(ui);
    const scale_changed = @abs(ui.font_render_scale - ui.render_scale) > 0.001;
    if (current_hash == ui.font_text_hash and !scale_changed) return;
    const next_codepoints = try buildFontCodepoints(ui);
    const next_font = loadFontAtlas(ui, next_codepoints) catch {
        ui.allocator.free(next_codepoints);
        ui.font_render_scale = ui.render_scale;
        return;
    };
    if (ui.font_loaded) rl.unloadFont(ui.font);
    ui.allocator.free(ui.font_codepoints);
    ui.font = next_font;
    ui.font_loaded = true;
    ui.font_codepoints = next_codepoints;
    ui.font_text_hash = current_hash;
    ui.font_render_scale = ui.render_scale;
}

fn loadFontAtlas(ui: *const UiState, codepoints: []const i32) !rl.Font {
    const pixel_size = @max(1, @as(i32, @intFromFloat(@ceil(pixelScale(ui, logical_font_size)))));
    const font = try font_atlas.load(embedded_assets.ttf, pixel_size, codepoints);
    if (!font.isReady()) return error.FontLoadFailed;
    rl.setTextureFilter(font.texture, .point);
    return font;
}

fn computeFontTextHash(ui: *UiState) u64 {
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(std.mem.asBytes(&ui.font_revision));
    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();
    hasher.update(ui.app.status_message);
    hasher.update(ui.search_buf[0..ui.search_len]);
    for (ui.app.rows.items) |row| {
        hasher.update(row.file.name);
        hasher.update(row.file.path);
        hasher.update(row.status);
    }
    return hasher.final();
}

fn buildFontCodepoints(ui: *UiState) ![]i32 {
    var seen = std.AutoHashMap(i32, void).init(ui.allocator);
    defer seen.deinit();
    var codepoints = try std.ArrayList(i32).initCapacity(ui.allocator, 256);
    errdefer codepoints.deinit(ui.allocator);

    try appendCodepointRange(&codepoints, &seen, 0x0020, 0x007E);
    try appendCodepointRange(&codepoints, &seen, 0x00A0, 0x00FF);
    try appendCodepointRange(&codepoints, &seen, 0x2000, 0x206F);
    try appendCodepointRange(&codepoints, &seen, 0x3000, 0x303F);
    try appendCodepointRange(&codepoints, &seen, 0xFF00, 0xFFEF);
    var drawn_it = ui.drawn_codepoints.keyIterator();
    while (drawn_it.next()) |cp| try appendCodepoint(&codepoints, &seen, cp.*);

    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();
    try appendTextCodepoints(&codepoints, &seen, ui.app.status_message);
    try appendTextCodepoints(&codepoints, &seen, ui.search_buf[0..ui.search_len]);
    for (ui.app.rows.items) |row| {
        try appendTextCodepoints(&codepoints, &seen, row.file.name);
        try appendTextCodepoints(&codepoints, &seen, row.file.path);
        try appendTextCodepoints(&codepoints, &seen, row.status);
    }
    return codepoints.toOwnedSlice(ui.allocator);
}

fn appendCodepointRange(codepoints: *std.ArrayList(i32), seen: *std.AutoHashMap(i32, void), first: i32, last: i32) !void {
    var cp = first;
    while (cp <= last) : (cp += 1) try appendCodepoint(codepoints, seen, cp);
}

fn appendTextCodepoints(codepoints: *std.ArrayList(i32), seen: *std.AutoHashMap(i32, void), text: []const u8) !void {
    var view = std.unicode.Utf8View.init(text) catch return;
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| try appendCodepoint(codepoints, seen, @intCast(cp));
}

fn trackDrawnText(ui: *UiState, text: []const u8) !void {
    var view = std.unicode.Utf8View.init(text) catch return;
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        const result = try ui.drawn_codepoints.getOrPut(@intCast(cp));
        if (!result.found_existing) ui.font_revision +%= 1;
    }
}

fn appendCodepoint(codepoints: *std.ArrayList(i32), seen: *std.AutoHashMap(i32, void), cp: i32) !void {
    const result = try seen.getOrPut(cp);
    if (result.found_existing) return;
    try codepoints.append(seen.allocator, cp);
}

fn handleDrops(ui: *UiState) void {
    if (!rl.isFileDropped()) return;
    const dropped = rl.loadDroppedFiles();
    defer rl.unloadDroppedFiles(dropped);
    var list: [64][]const u8 = undefined;
    const n = @min(@as(usize, @intCast(dropped.count)), list.len);
    for (0..n) |i| list[i] = std.mem.span(dropped.paths[i]);
    ui.app.addDroppedPaths(list[0..n]);
}

fn handleSearchInput(ui: *UiState) void {
    if (!ui.search_active) return;
    if (rl.isKeyPressed(.backspace) and ui.search_len > 0) {
        ui.search_len = prevUtf8Start(ui.search_buf[0..ui.search_len]);
        ui.search_buf[ui.search_len] = 0;
    }
    while (true) {
        const cp = rl.getCharPressed();
        if (cp == 0) break;
        if (ui.search_len + 4 >= ui.search_buf.len) continue;
        ui.search_len += encodeUtf8(@intCast(cp), ui.search_buf[ui.search_len .. ui.search_buf.len - 1]) catch 0;
        ui.search_buf[ui.search_len] = 0;
    }
}

fn prevUtf8Start(text: []const u8) usize {
    if (text.len == 0) return 0;
    var i = text.len - 1;
    while (i > 0 and (text[i] & 0b1100_0000) == 0b1000_0000) i -= 1;
    return i;
}

fn encodeUtf8(cp: u21, out: []u8) !usize {
    if (cp <= 0x7F) {
        out[0] = @intCast(cp);
        return 1;
    } else if (cp <= 0x7FF) {
        out[0] = @intCast(0xC0 | (cp >> 6));
        out[1] = @intCast(0x80 | (cp & 0x3F));
        return 2;
    } else if (cp <= 0xFFFF) {
        out[0] = @intCast(0xE0 | (cp >> 12));
        out[1] = @intCast(0x80 | ((cp >> 6) & 0x3F));
        out[2] = @intCast(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = @intCast(0xF0 | (cp >> 18));
    out[1] = @intCast(0x80 | ((cp >> 12) & 0x3F));
    out[2] = @intCast(0x80 | ((cp >> 6) & 0x3F));
    out[3] = @intCast(0x80 | (cp & 0x3F));
    return 4;
}

fn handleWindowDrag(ui: *UiState) void {
    if (@import("builtin").os.tag == .windows) return;
    const mouse = rl.getMousePosition();
    const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
    const in_title = mouse.y >= 0 and mouse.y <= scale(ui, 34) and mouse.x < screen_w - scale(ui, 132);
    if (resizeHitTest(ui, mouse) != null) return;
    if (@import("builtin").os.tag == .windows and in_title and rl.isMouseButtonPressed(.left)) {
        windows_frame.beginWindowDrag(rl.getWindowHandle());
        ui.dragging_title = false;
        return;
    }
    const down = rl.isMouseButtonDown(.left);
    if (in_title and rl.isMouseButtonPressed(.left)) {
        ui.dragging_title = true;
        ui.drag_mouse_start = mouse;
        ui.drag_window_start = rl.getWindowPosition();
    }
    if (ui.dragging_title and down) {
        const dpi = rl.getWindowScaleDPI();
        const dx = (mouse.x - ui.drag_mouse_start.x) * dpi.x;
        const dy = (mouse.y - ui.drag_mouse_start.y) * dpi.y;
        rl.setWindowPosition(@intFromFloat(ui.drag_window_start.x + dx), @intFromFloat(ui.drag_window_start.y + dy));
    }
    if (!down) ui.dragging_title = false;
}

fn handleWindowResize(ui: *UiState) void {
    const mouse = rl.getMousePosition();
    const hit = resizeHitTest(ui, mouse);
    if (hit) |ht| {
        setResizeCursor(ui, ht);
        if (@import("builtin").os.tag == .windows) return;
        if (@import("builtin").os.tag == .windows and rl.isMouseButtonPressed(.left)) {
            windows_frame.beginWindowResize(rl.getWindowHandle(), ht);
        }
    }
}

fn resizeHitTest(ui: *UiState, mouse: Vec2) ?c_int {
    if (rl.isWindowMaximized()) return null;
    const w: f32 = @floatFromInt(rl.getScreenWidth());
    const h: f32 = @floatFromInt(rl.getScreenHeight());
    const edge = scale(ui, 7);
    const left = mouse.x >= 0 and mouse.x <= edge;
    const right = mouse.x >= w - edge and mouse.x <= w;
    const top = mouse.y >= 0 and mouse.y <= edge;
    const bottom = mouse.y >= h - edge and mouse.y <= h;

    if (top and left) return 13;
    if (top and right) return 14;
    if (bottom and left) return 16;
    if (bottom and right) return 17;
    if (left) return 10;
    if (right) return 11;
    if (top) return 12;
    if (bottom) return 15;
    return null;
}

fn setResizeCursor(ui: *UiState, hit: c_int) void {
    switch (hit) {
        10, 11 => requestCursor(ui, .resize_ew),
        12, 15 => requestCursor(ui, .resize_ns),
        13, 17 => requestCursor(ui, .resize_nwse),
        14, 16 => requestCursor(ui, .resize_nesw),
        else => {},
    }
}

fn drawFrame(ui: *UiState) void {
    const w: f32 = @floatFromInt(rl.getScreenWidth());
    const h: f32 = @floatFromInt(rl.getScreenHeight());
    rl.drawRectangleRec(rect(0, 0, w, h), colors.bg);
    drawTitleBar(ui, w);
    const toolbar_bottom = drawToolbar(ui, w);
    const options_bottom = drawOptions(ui, w, toolbar_bottom + scale(ui, 8));
    const status_bottom = drawStatus(ui, w, options_bottom + scale(ui, 8));
    drawTable(ui, w, h, status_bottom + scale(ui, 8));
    if (ui.filter_open) drawFilterPopup(ui);
}

fn drawTitleBar(ui: *UiState, w: f32) void {
    const h = scale(ui, 34);
    rl.drawRectangleRec(rect(0, 0, w, h), colors.bg);
    const icon_size = scale(ui, 20);
    const icon_x = scale(ui, 8);
    const icon_y = (h - icon_size) * 0.5;
    if (ui.app_icon_loaded) {
        rl.drawTexturePro(
            ui.app_icon,
            rect(0, 0, @floatFromInt(ui.app_icon.width), @floatFromInt(ui.app_icon.height)),
            rect(icon_x, icon_y, icon_size, icon_size),
            .{ .x = 0, .y = 0 },
            0,
            Color.init(255, 255, 255, 255),
        );
    }
    drawTextClipped(ui, "Hasher 1.4", rect(scale(ui, 34), scale(ui, 7), scale(ui, 180), scale(ui, 22)), colors.text);
    var x = w - scale(ui, 112);
    if (iconButton(ui, rect(x, scale(ui, 4), scale(ui, 32), scale(ui, 26)), .minimize, colors.button)) {
        if (@import("builtin").os.tag == .windows) windows_frame.minimize(rl.getWindowHandle()) else rl.minimizeWindow();
    }
    x += scale(ui, 36);
    if (iconButton(ui, rect(x, scale(ui, 4), scale(ui, 32), scale(ui, 26)), if (rl.isWindowMaximized()) .restore else .maximize, colors.button)) {
        if (@import("builtin").os.tag == .windows) {
            windows_frame.toggleMaximize(rl.getWindowHandle(), rl.isWindowMaximized());
        } else if (rl.isWindowMaximized()) {
            rl.restoreWindow();
        } else {
            rl.maximizeWindow();
        }
    }
    x += scale(ui, 36);
    if (iconButton(ui, rect(x, scale(ui, 4), scale(ui, 32), scale(ui, 26)), .close, colors.danger)) {
        if (@import("builtin").os.tag == .windows) windows_frame.close(rl.getWindowHandle()) else rl.closeWindow();
    }
    rl.drawLine(0, @intFromFloat(h - 1), @intFromFloat(w), @intFromFloat(h - 1), colors.border);
}

fn drawToolbar(ui: *UiState, w: f32) f32 {
    worker.lockMutex(&ui.app.mutex);
    const processing = ui.app.processing;
    ui.app.mutex.unlock();

    var flow = FlowLayout.init(scale(ui, 6), scale(ui, 42), w - scale(ui, 6), scale(ui, 30), scale(ui, 6), scale(ui, 6));
    if (toolButtonState(ui, flow.next(scale(ui, 72)), .play, "开始", !processing, false)) ui.app.start() catch {};
    if (toolButtonState(ui, flow.next(scale(ui, 72)), .stop, "停止", processing, processing)) ui.app.stop();
    if (toolButton(ui, flow.next(scale(ui, 72)), .clear, "清空")) ui.app.clear();
    if (toolButton(ui, flow.next(scale(ui, 74)), .copy, "复制")) copyRows(ui, true) catch {};
    if (toolButton(ui, flow.next(scale(ui, 74)), .save, "保存")) saveRows(ui, true) catch {};
    if (toolButton(ui, flow.next(scale(ui, 124)), .copy_no_path, "复制无路径")) copyRows(ui, false) catch {};
    if (toolButton(ui, flow.next(scale(ui, 124)), .save_no_path, "保存无路径")) saveRows(ui, false) catch {};
    const filter_rect = flow.next(scale(ui, 128));
    ui.filter_button_rect = filter_rect;
    if (filterButton(ui, filter_rect)) ui.filter_open = !ui.filter_open;
    drawSearch(ui, flow.next(scale(ui, 270)));
    if (toolButton(ui, flow.next(scale(ui, 72)), .reset, "重置")) {
        @memset(&ui.search_buf, 0);
        ui.search_len = 0;
    }
    return flow.bottom();
}

fn drawOptions(ui: *UiState, screen_w: f32, start_y: f32) f32 {
    worker.lockMutex(&ui.app.mutex);
    const row_h = scale(ui, 24);
    var flow = FlowLayout.init(scale(ui, 6), start_y, screen_w - scale(ui, 6), row_h, scale(ui, 8), scale(ui, 4));
    for (hash.all_algorithms) |algorithm| {
        const wide: f32 = if (algorithm == .crc64_iso or algorithm == .crc64_ecma) 126 else 86;
        const sw = scale(ui, wide);
        var enabled = ui.app.options.enabled(algorithm);
        if (checkbox(ui, flow.next(sw), algorithmLabelZ(algorithm), &enabled)) {
            ui.app.options.set(algorithm, enabled);
        }
    }
    _ = checkbox(ui, flow.next(scale(ui, 78)), "大写", &ui.app.uppercase);
    const menu_button_w = scale(ui, 142);
    const configure_context_menu = toolButton(ui, flow.next(menu_button_w), .settings, if (ui.context_menu_enabled) "关闭右键菜单" else "开启右键菜单");
    ui.app.mutex.unlock();
    if (configure_context_menu) configureContextMenu(ui);
    return flow.bottom();
}

fn drawStatus(ui: *UiState, w: f32, y: f32) f32 {
    var buf: [160]u8 = undefined;
    worker.lockMutex(&ui.app.mutex);
    const done = ui.app.progress_done;
    const total = ui.app.progress_total;
    const processing = ui.app.processing;
    const text = std.fmt.bufPrint(&buf, "{s} {d}/{d}{s}", .{ ui.app.status_message, done, total, if (processing) " ..." else "" }) catch "状态不可用";
    ui.app.mutex.unlock();

    const pct: f32 = if (total == 0) 0 else @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(total));
    const status_w = @min(measureText(ui, text, w) + scale(ui, 4), @max(scale(ui, 100), w - scale(ui, 180)));
    drawTextClipped(ui, text, rect(scale(ui, 6), y + scale(ui, 2), status_w, scale(ui, 20)), colors.text);
    const progress_x = scale(ui, 6) + status_w + scale(ui, 10);
    const progress = rect(progress_x, y + scale(ui, 2), @max(scale(ui, 150), w - progress_x - scale(ui, 6)), scale(ui, 20));
    rl.drawRectangleRounded(progress, 0.22, 6, colors.panel2);
    rl.drawRectangleRounded(rect(progress.x, progress.y, progress.width * pct, progress.height), 0.22, 6, colors.accent.alpha(0.55));
    rl.drawRectangleRoundedLinesEx(progress, 0.22, 6, 1, colors.border);
    return y + scale(ui, 24);
}

fn drawTable(ui: *UiState, w: f32, h: f32, top: f32) void {
    const margin = scale(ui, 6);
    const scrollbar_size = scale(ui, 12);
    const bottom = h - margin;
    const row_h = scale(ui, 28);
    const header_h = scale(ui, 28);
    const vscroll_w = scrollbar_size;
    const table_w = w - scale(ui, 12);
    const table_x = scale(ui, 6);
    const table_h = bottom - top;
    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();

    const content_w = totalTableWidth(ui, ui.app.options, table_w);
    const max_scroll_x = @max(0, content_w - table_w);
    ui.table_scroll_x = std.math.clamp(ui.table_scroll_x, 0, max_scroll_x);

    var visible_index: usize = 0;
    rl.drawRectangleRounded(rect(table_x, top, table_w, table_h), 0.018, 8, colors.panel);
    rl.drawRectangleRoundedLinesEx(rect(table_x, top, table_w, table_h), 0.018, 8, 1, colors.border);
    const body = rect(table_x, top + header_h, table_w, table_h - header_h - scrollbar_size);
    handleTableScroll(ui, body, row_h, content_w);
    {
        beginScissor(ui, body);
        defer rl.endScissorMode();
        for (ui.app.rows.items) |row| {
            if (!rowMatches(ui, row)) continue;
            const row_y = body.y + @as(f32, @floatFromInt(visible_index)) * row_h - ui.table_scroll_y;
            if (row_y + row_h >= body.y and row_y <= body.y + body.height) drawRow(ui, row, table_x - ui.table_scroll_x, row_y, row_h, visible_index, ui.app.options);
            visible_index += 1;
        }
    }
    const max_scroll_y = @max(0, @as(f32, @floatFromInt(visible_index)) * row_h - body.height);
    ui.table_scroll_y = std.math.clamp(ui.table_scroll_y, 0, max_scroll_y);

    drawTableHeader(ui, table_x, top, table_w, header_h, ui.app.options);
    drawHorizontalScroll(ui, rect(table_x, bottom - scrollbar_size, table_w, scrollbar_size), content_w);
    drawVerticalScroll(ui, rect(table_x + table_w - vscroll_w, body.y, vscroll_w, body.height), @as(f32, @floatFromInt(visible_index)) * row_h);
}

fn handleTableScroll(ui: *UiState, area: Rect, row_h: f32, content_w: f32) void {
    _ = row_h;
    if (!rl.checkCollisionPointRec(rl.getMousePosition(), area)) return;
    const wheel = rl.getMouseWheelMoveV();
    if (wheel.y != 0) {
        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
            ui.table_scroll_x -= wheel.y * scale(ui, 42);
        } else {
            ui.table_scroll_y -= wheel.y * scale(ui, 42);
        }
    }
    ui.table_scroll_x = std.math.clamp(ui.table_scroll_x, 0, @max(0, content_w - area.width));
}

fn drawTableHeader(ui: *UiState, x: f32, y: f32, width: f32, h: f32, options: hash.HashOptions) void {
    rl.drawRectangleRounded(rect(x, y, width, h), 0.10, 6, colors.panel2);
    rl.drawLine(@intFromFloat(x), @intFromFloat(y + h - 1), @intFromFloat(x + width), @intFromFloat(y + h - 1), colors.border);
    var col_x = x - ui.table_scroll_x;
    pushHeader(ui, &col_x, y, h, 0, "文件");
    pushHeader(ui, &col_x, y, h, 1, "大小");
    for (hash.all_algorithms) |algorithm| {
        if (options.enabled(algorithm)) pushHeader(ui, &col_x, y, h, 2 + @intFromEnum(algorithm), algorithmLabelZ(algorithm));
    }
    pushHeader(ui, &col_x, y, h, 10, "状态");
    pushHeaderWidth(ui, &col_x, y, h, 11, "完整路径", pathColumnWidth(ui, options, width));
}

fn pushHeader(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, text: []const u8) void {
    pushHeaderWidth(ui, x, y, h, column, text, scale(ui, ui.column_widths[column]));
}

fn pushHeaderWidth(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, text: []const u8, sw: f32) void {
    const right = x.* + sw;
    const mouse = rl.getMousePosition();
    const grip = rect(right - scale(ui, 4), y, scale(ui, 8), h);
    if (rl.checkCollisionPointRec(mouse, grip)) requestCursor(ui, .resize_ew);
    if (rl.checkCollisionPointRec(mouse, grip) and rl.isMouseButtonPressed(.left)) ui.resizing_column = column;
    if (ui.resizing_column == column and rl.isMouseButtonDown(.left)) {
        const logical_right = mouse.x + ui.table_scroll_x;
        const logical_left = x.* + ui.table_scroll_x;
        ui.column_widths[column] = @max(54, logical_right - logical_left);
    }
    if (!rl.isMouseButtonDown(.left) and ui.resizing_column == column) ui.resizing_column = null;
    rl.drawLine(@intFromFloat(right), @intFromFloat(y), @intFromFloat(right), @intFromFloat(y + h), colors.border);
    drawTextClipped(ui, text, rect(x.* + scale(ui, 6), y + scale(ui, 5), sw - scale(ui, 12), h - scale(ui, 8)), colors.text);
    x.* += sw;
}

fn drawRow(ui: *UiState, row: worker.Row, x: f32, y: f32, h: f32, index: usize, options: hash.HashOptions) void {
    const row_rect = rect(scale(ui, 6), y, @as(f32, @floatFromInt(rl.getScreenWidth())) - scale(ui, 12), h);
    const hovered = rl.checkCollisionPointRec(rl.getMousePosition(), row_rect);
    const bg = if (hovered) colors.row_hover else if (index % 2 == 0) colors.bg else colors.row_alt;
    rl.drawRectangleRec(row_rect, bg);
    if (hovered) rl.drawLine(@intFromFloat(row_rect.x), @intFromFloat(y + h - 1), @intFromFloat(row_rect.x + row_rect.width), @intFromFloat(y + h - 1), colors.accent.alpha(0.35));
    var col_x = x;
    pushCellColored(ui, &col_x, y, h, 0, index, row.file.name, colors.text);
    pushCellColored(ui, &col_x, y, h, 1, index, row.file.size_label, colors.muted);
    for (hash.all_algorithms) |algorithm| {
        if (options.enabled(algorithm)) pushHashCell(ui, &col_x, y, h, 2 + @intFromEnum(algorithm), index, row.result.get(algorithm));
    }
    pushCellColored(ui, &col_x, y, h, 10, index, row.status, statusColor(row.status));
    pushCellWidthColored(ui, &col_x, y, h, 11, index, row.file.path, pathColumnWidth(ui, options, @as(f32, @floatFromInt(rl.getScreenWidth())) - scale(ui, 12)), colors.path);
}

fn pushCell(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, row: usize, text: []const u8) void {
    pushCellColored(ui, x, y, h, column, row, text, colors.text);
}

fn pushCellColored(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, row: usize, text: []const u8, color: Color) void {
    pushCellWidthColored(ui, x, y, h, column, row, text, scale(ui, ui.column_widths[column]), color);
}

fn pushCellWidthColored(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, row: usize, text: []const u8, sw: f32, color: Color) void {
    const cell = rect(x.*, y, sw, h);
    const selected = ui.selected_row == row and ui.selected_column == column;
    if (selected) {
        rl.drawRectangleRec(cell, colors.selected.alpha(0.72));
        rl.drawRectangleLinesEx(rect(cell.x + 1, cell.y + 1, cell.width - 2, cell.height - 2), 1, colors.accent);
    }
    const mouse = rl.getMousePosition();
    if (rl.checkCollisionPointRec(mouse, cell) and rl.isMouseButtonReleased(.left) and ui.resizing_column == null) {
        ui.selected_row = row;
        ui.selected_column = column;
        const ztext = ui.allocator.dupeZ(u8, text) catch null;
        if (ztext) |z| {
            defer ui.allocator.free(z);
            rl.setClipboardText(z);
        }
    }
    rl.drawLine(@intFromFloat(x.* + sw), @intFromFloat(y), @intFromFloat(x.* + sw), @intFromFloat(y + h), colors.border.alpha(0.6));
    drawTextClipped(ui, text, rect(x.* + scale(ui, 6), y + scale(ui, 5), sw - scale(ui, 12), h - scale(ui, 8)), color);
    x.* += sw;
}

fn pushHashCell(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, row: usize, text: []const u8) void {
    if (!ui.app.uppercase) return pushCellColored(ui, x, y, h, column, row, text, colors.hash_value);
    var buf: [128]u8 = undefined;
    pushCellColored(ui, x, y, h, column, row, uppercaseInto(&buf, text), colors.hash_value);
}

fn statusColor(status: []const u8) Color {
    if (std.mem.indexOf(u8, status, "错误") != null) return colors.danger;
    if (std.mem.eql(u8, status, "完成")) return colors.success;
    if (std.mem.eql(u8, status, "排队中") or std.mem.eql(u8, status, "等待中")) return colors.warning;
    return colors.accent;
}

fn drawHorizontalScroll(ui: *UiState, area: Rect, content_w: f32) void {
    rl.drawRectangleRounded(area, 0.45, 8, colors.scrollbar_track);
    const max_scroll = @max(0, content_w - area.width);
    if (max_scroll <= 0) return;
    const handle_w = @max(scale(ui, 56), area.width * (area.width / content_w));
    const range = area.width - handle_w;
    var handle_x = area.x + range * (ui.table_scroll_x / max_scroll);
    var handle = rect(handle_x, area.y + scale(ui, 2), handle_w, area.height - scale(ui, 4));
    const mouse = rl.getMousePosition();
    const hover = rl.checkCollisionPointRec(mouse, handle);
    if (hover or ui.dragging_hscroll) requestCursor(ui, .resize_ew);
    if (rl.isMouseButtonPressed(.left) and rl.checkCollisionPointRec(mouse, area)) {
        ui.dragging_hscroll = true;
        if (hover) {
            ui.hscroll_grab_offset = mouse.x - handle_x;
        } else {
            handle_x = std.math.clamp(mouse.x - handle_w * 0.5, area.x, area.x + range);
            ui.hscroll_grab_offset = handle_w * 0.5;
            ui.table_scroll_x = ((handle_x - area.x) / range) * max_scroll;
        }
    }
    if (!rl.isMouseButtonDown(.left)) ui.dragging_hscroll = false;
    if (ui.dragging_hscroll) {
        handle_x = std.math.clamp(mouse.x - ui.hscroll_grab_offset, area.x, area.x + range);
        ui.table_scroll_x = ((handle_x - area.x) / range) * max_scroll;
    }
    handle.x = handle_x;
    rl.drawRectangleRounded(handle, 0.7, 8, if (ui.dragging_hscroll) colors.accent else if (hover) colors.accent_hover else colors.scrollbar_thumb);
}

fn drawVerticalScroll(ui: *UiState, area: Rect, content_h: f32) void {
    rl.drawRectangleRounded(area, 0.45, 8, colors.scrollbar_track);
    const max_scroll = @max(0, content_h - area.height);
    if (max_scroll <= 0) return;
    const handle_h = @max(scale(ui, 56), area.height * (area.height / content_h));
    const range = area.height - handle_h;
    var handle_y = area.y + range * (ui.table_scroll_y / max_scroll);
    var handle = rect(area.x + scale(ui, 2), handle_y, area.width - scale(ui, 4), handle_h);
    const mouse = rl.getMousePosition();
    const hover = rl.checkCollisionPointRec(mouse, handle);
    if (hover or ui.dragging_vscroll) requestCursor(ui, .resize_ns);
    if (rl.isMouseButtonPressed(.left) and rl.checkCollisionPointRec(mouse, area)) {
        ui.dragging_vscroll = true;
        if (hover) {
            ui.vscroll_grab_offset = mouse.y - handle_y;
        } else {
            handle_y = std.math.clamp(mouse.y - handle_h * 0.5, area.y, area.y + range);
            ui.vscroll_grab_offset = handle_h * 0.5;
            ui.table_scroll_y = ((handle_y - area.y) / range) * max_scroll;
        }
    }
    if (!rl.isMouseButtonDown(.left)) ui.dragging_vscroll = false;
    if (ui.dragging_vscroll) {
        handle_y = std.math.clamp(mouse.y - ui.vscroll_grab_offset, area.y, area.y + range);
        ui.table_scroll_y = ((handle_y - area.y) / range) * max_scroll;
    }
    handle.y = handle_y;
    rl.drawRectangleRounded(handle, 0.7, 8, if (ui.dragging_vscroll) colors.accent else if (hover) colors.accent_hover else colors.scrollbar_thumb);
}

fn totalTableWidth(ui: *UiState, options: hash.HashOptions, viewport_w: f32) f32 {
    const total = fixedTableWidth(ui, options) + pathColumnWidth(ui, options, viewport_w);
    return total;
}

fn fixedTableWidth(ui: *UiState, options: hash.HashOptions) f32 {
    var total = ui.column_widths[0] + ui.column_widths[1] + ui.column_widths[10];
    for (hash.all_algorithms) |algorithm| {
        if (options.enabled(algorithm)) total += ui.column_widths[2 + @intFromEnum(algorithm)];
    }
    return scale(ui, total);
}

fn pathColumnWidth(ui: *UiState, options: hash.HashOptions, viewport_w: f32) f32 {
    return @max(scale(ui, ui.column_widths[11]), viewport_w - fixedTableWidth(ui, options));
}

fn toolButton(ui: *UiState, r: Rect, icon: Icon, label: []const u8) bool {
    return toolButtonState(ui, r, icon, label, true, false);
}

fn toolButtonState(ui: *UiState, r: Rect, icon: Icon, label: []const u8, enabled: bool, active: bool) bool {
    const base = if (active) colors.danger else colors.button;
    const visual = buttonBaseVisual(r, base, if (active) colors.close_hover else colors.button_hover, if (active) colors.close_down else colors.button_down, enabled);
    const offset = if (visual.pressed) scale(ui, 1) else 0;
    const foreground = if (enabled) colors.text else colors.muted.alpha(0.62);
    drawIcon(icon, rect(r.x + scale(ui, 8), r.y + scale(ui, 7) + offset, scale(ui, 16), scale(ui, 16)), foreground);
    drawTextClipped(ui, label, rect(r.x + scale(ui, 30), r.y + scale(ui, 6) + offset, r.width - scale(ui, 34), r.height - scale(ui, 8)), foreground);
    return visual.clicked;
}

fn configureContextMenu(ui: *UiState) void {
    const enable = !ui.context_menu_enabled;
    if (enable) context_menu.install(ui.allocator) catch {
        worker.lockMutex(&ui.app.mutex);
        defer ui.app.mutex.unlock();
        ui.app.setMessageLocked("右键菜单配置失败");
        return;
    } else context_menu.uninstall(ui.allocator) catch {
        worker.lockMutex(&ui.app.mutex);
        defer ui.app.mutex.unlock();
        ui.app.setMessageLocked("右键菜单关闭失败");
        return;
    };
    ui.context_menu_enabled = enable;
    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();
    ui.app.setMessageLocked(if (enable) "右键菜单已开启" else "右键菜单已关闭");
}

fn iconButton(ui: *UiState, r: Rect, icon: Icon, base: Color) bool {
    const visual = if (icon == .close)
        buttonBaseVisual(r, base, colors.close_hover, colors.close_down, true)
    else
        buttonBaseVisual(r, base, colors.button_hover, colors.button_down, true);
    const offset = if (visual.pressed) scale(ui, 1) else 0;
    drawIcon(icon, rect(r.x + scale(ui, 8), r.y + scale(ui, 6) + offset, r.width - scale(ui, 16), r.height - scale(ui, 12)), colors.text);
    return visual.clicked;
}

fn buttonBase(r: Rect, base: Color) bool {
    return buttonBaseColors(r, base, colors.button_hover, colors.button_down);
}

fn buttonBaseColors(r: Rect, base: Color, hover_color: Color, down_color: Color) bool {
    return buttonBaseVisual(r, base, hover_color, down_color, true).clicked;
}

fn buttonBaseVisual(r: Rect, base: Color, hover_color: Color, down_color: Color, enabled: bool) ButtonVisual {
    const mouse = rl.getMousePosition();
    const hover = enabled and rl.checkCollisionPointRec(mouse, r);
    const down = hover and rl.isMouseButtonDown(.left);
    rl.drawRectangleRounded(rect(r.x, r.y + 1, r.width, r.height), 0.12, 6, Color.init(0, 0, 0, 80));
    rl.drawRectangleRounded(r, 0.12, 6, if (!enabled) colors.button_disabled else if (down) down_color else if (hover) hover_color else base);
    rl.drawRectangleRoundedLinesEx(r, 0.12, 6, 1, if (hover) colors.accent.alpha(0.78) else colors.border);
    return .{ .clicked = hover and rl.isMouseButtonReleased(.left), .hovered = hover, .pressed = down };
}

fn filterButton(ui: *UiState, r: Rect) bool {
    const visual = buttonBaseVisual(r, colors.button, colors.button_hover, colors.button_down, true);
    const offset = if (visual.pressed) scale(ui, 1) else 0;
    drawTextClipped(ui, currentFilterLabel(ui), rect(r.x + scale(ui, 10), r.y + scale(ui, 6) + offset, r.width - scale(ui, 34), r.height - scale(ui, 8)), colors.text);
    drawIcon(.chevron_down, rect(r.x + r.width - scale(ui, 24), r.y + scale(ui, 8) + offset, scale(ui, 14), scale(ui, 14)), colors.text);
    return visual.clicked;
}

fn drawFilterPopup(ui: *UiState) void {
    const row_h = scale(ui, 24);
    const w = @max(ui.filter_button_rect.width, scale(ui, 154));
    const popup_h = row_h * @as(f32, @floatFromInt(filter_labels.len));
    const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
    const x = std.math.clamp(ui.filter_button_rect.x, scale(ui, 4), @max(scale(ui, 4), screen_w - w - scale(ui, 4)));
    var y = ui.filter_button_rect.y + ui.filter_button_rect.height + scale(ui, 3);
    if (y + popup_h > screen_h - scale(ui, 4)) {
        y = @max(scale(ui, 4), ui.filter_button_rect.y - popup_h - scale(ui, 3));
    }
    const mouse = rl.getMousePosition();
    const popup = rect(x, y, w, popup_h);
    rl.drawRectangleRec(popup, colors.panel);
    rl.drawRectangleLinesEx(popup, 1, colors.border);
    for (filter_labels, 0..) |label, i| {
        const rr = rect(x, y + row_h * @as(f32, @floatFromInt(i)), w, row_h);
        const hover = rl.checkCollisionPointRec(mouse, rr);
        if (hover) rl.drawRectangleRec(rr, colors.button_hover);
        drawTextClipped(ui, label, rect(rr.x + scale(ui, 8), rr.y + scale(ui, 4), rr.width - scale(ui, 12), rr.height - scale(ui, 6)), colors.text);
        if (hover and rl.isMouseButtonReleased(.left)) {
            ui.filter_column = @intCast(i);
            ui.filter_open = false;
        }
    }
    if (rl.isMouseButtonPressed(.left) and !rl.checkCollisionPointRec(mouse, popup)) ui.filter_open = false;
}

fn drawSearch(ui: *UiState, r: Rect) void {
    const mouse = rl.getMousePosition();
    if (rl.isMouseButtonPressed(.left)) ui.search_active = rl.checkCollisionPointRec(mouse, r);
    rl.drawRectangleRounded(r, 0.1, 6, colors.input);
    rl.drawRectangleRoundedLinesEx(r, 0.1, 6, 1, if (ui.search_active) colors.accent else colors.border);
    const text = ui.search_buf[0..ui.search_len];
    drawTextClipped(ui, if (text.len == 0 and !ui.search_active) "搜索" else text, rect(r.x + scale(ui, 8), r.y + scale(ui, 6), r.width - scale(ui, 14), r.height - scale(ui, 8)), if (text.len == 0) colors.muted else colors.text);
    if (ui.search_active and (@mod(@as(i32, @intFromFloat(rl.getTime() * 2)), 2) == 0)) {
        const tw = measureText(ui, text, r.width - scale(ui, 18));
        rl.drawLine(@intFromFloat(r.x + scale(ui, 9) + tw), @intFromFloat(r.y + scale(ui, 7)), @intFromFloat(r.x + scale(ui, 9) + tw), @intFromFloat(r.y + r.height - scale(ui, 7)), colors.text);
    }
}

fn checkbox(ui: *UiState, r: Rect, label: []const u8, value: *bool) bool {
    const mouse = rl.getMousePosition();
    const hover = rl.checkCollisionPointRec(mouse, r);
    if (hover and rl.isMouseButtonReleased(.left)) value.* = !value.*;
    if (hover) rl.drawRectangleRounded(r, 0.12, 6, colors.panel2.alpha(0.72));
    const box = rect(r.x, r.y + scale(ui, 3), scale(ui, 17), scale(ui, 17));
    rl.drawRectangleRounded(box, 0.22, 6, if (value.*) colors.accent else colors.input);
    rl.drawRectangleRoundedLinesEx(box, 0.22, 6, 1, if (hover) colors.accent_hover else colors.border);
    if (value.*) drawIcon(.check, rect(box.x + scale(ui, 3), box.y + scale(ui, 3), box.width - scale(ui, 6), box.height - scale(ui, 6)), colors.text);
    drawTextClipped(ui, label, rect(r.x + scale(ui, 24), r.y + scale(ui, 2), r.width - scale(ui, 26), r.height - scale(ui, 4)), colors.text);
    return hover and rl.isMouseButtonReleased(.left);
}

fn drawIcon(icon: Icon, r: Rect, color: Color) void {
    const x = r.x;
    const y = r.y;
    const w = r.width;
    const h = r.height;
    const thick = @max(1.4, w * 0.11);
    switch (icon) {
        .minimize => rl.drawLineEx(vec(x + w * 0.18, y + h * 0.68), vec(x + w * 0.82, y + h * 0.68), thick, color),
        .maximize => rl.drawRectangleLinesEx(rect(x + w * 0.20, y + h * 0.20, w * 0.60, h * 0.60), thick, color),
        .restore => {
            rl.drawRectangleLinesEx(rect(x + w * 0.28, y + h * 0.18, w * 0.52, h * 0.52), thick, color);
            rl.drawRectangleLinesEx(rect(x + w * 0.18, y + h * 0.30, w * 0.52, h * 0.52), thick, color);
        },
        .close => {
            rl.drawLineEx(vec(x + w * 0.22, y + h * 0.22), vec(x + w * 0.78, y + h * 0.78), thick, color);
            rl.drawLineEx(vec(x + w * 0.78, y + h * 0.22), vec(x + w * 0.22, y + h * 0.78), thick, color);
        },
        .check => {
            rl.drawLineEx(vec(x + w * 0.18, y + h * 0.55), vec(x + w * 0.42, y + h * 0.78), thick, color);
            rl.drawLineEx(vec(x + w * 0.42, y + h * 0.78), vec(x + w * 0.84, y + h * 0.24), thick, color);
        },
        .play => rl.drawTriangle(vec(x + w * 0.28, y + h * 0.18), vec(x + w * 0.28, y + h * 0.82), vec(x + w * 0.82, y + h * 0.50), color),
        .stop => rl.drawRectangleRec(rect(x + w * 0.24, y + h * 0.24, w * 0.52, h * 0.52), color),
        .clear => {
            rl.drawLineEx(vec(x + w * 0.25, y + h * 0.32), vec(x + w * 0.75, y + h * 0.32), thick, color);
            rl.drawRectangleLinesEx(rect(x + w * 0.30, y + h * 0.38, w * 0.40, h * 0.42), thick, color);
            rl.drawLineEx(vec(x + w * 0.42, y + h * 0.18), vec(x + w * 0.58, y + h * 0.18), thick, color);
        },
        .copy, .copy_no_path => {
            rl.drawRectangleLinesEx(rect(x + w * 0.30, y + h * 0.20, w * 0.44, h * 0.54), thick, color);
            rl.drawRectangleLinesEx(rect(x + w * 0.18, y + h * 0.34, w * 0.44, h * 0.48), thick, color);
            if (icon == .copy_no_path) rl.drawLineEx(vec(x + w * 0.18, y + h * 0.18), vec(x + w * 0.82, y + h * 0.82), thick, colors.accent);
        },
        .save, .save_no_path => {
            rl.drawRectangleLinesEx(rect(x + w * 0.24, y + h * 0.20, w * 0.52, h * 0.60), thick, color);
            rl.drawLineEx(vec(x + w * 0.34, y + h * 0.20), vec(x + w * 0.34, y + h * 0.44), thick, color);
            rl.drawLineEx(vec(x + w * 0.66, y + h * 0.20), vec(x + w * 0.66, y + h * 0.44), thick, color);
            rl.drawRectangleLinesEx(rect(x + w * 0.34, y + h * 0.56, w * 0.32, h * 0.18), thick, color);
            if (icon == .save_no_path) rl.drawLineEx(vec(x + w * 0.18, y + h * 0.18), vec(x + w * 0.82, y + h * 0.82), thick, colors.accent);
        },
        .reset => {
            rl.drawCircleLinesV(vec(x + w * 0.50, y + h * 0.52), w * 0.28, color);
            rl.drawTriangle(vec(x + w * 0.28, y + h * 0.24), vec(x + w * 0.52, y + h * 0.20), vec(x + w * 0.42, y + h * 0.42), color);
        },
        .chevron_down => {
            rl.drawLineEx(vec(x + w * 0.20, y + h * 0.35), vec(x + w * 0.50, y + h * 0.68), thick, color);
            rl.drawLineEx(vec(x + w * 0.80, y + h * 0.35), vec(x + w * 0.50, y + h * 0.68), thick, color);
        },
        .settings => {
            rl.drawCircleLinesV(vec(x + w * 0.50, y + h * 0.50), w * 0.26, color);
            rl.drawCircleV(vec(x + w * 0.50, y + h * 0.50), w * 0.08, color);
            rl.drawLineEx(vec(x + w * 0.50, y + h * 0.10), vec(x + w * 0.50, y + h * 0.25), thick, color);
            rl.drawLineEx(vec(x + w * 0.50, y + h * 0.75), vec(x + w * 0.50, y + h * 0.90), thick, color);
            rl.drawLineEx(vec(x + w * 0.10, y + h * 0.50), vec(x + w * 0.25, y + h * 0.50), thick, color);
            rl.drawLineEx(vec(x + w * 0.75, y + h * 0.50), vec(x + w * 0.90, y + h * 0.50), thick, color);
        },
    }
}

fn drawTextClipped(ui: *UiState, text: []const u8, r: Rect, color: Color) void {
    if (r.width <= 2 or r.height <= 2) return;
    trackDrawnText(ui, text) catch {};
    var cps: [512]i32 = undefined;
    const n = textToCodepoints(text, &cps);
    var draw_n = n;
    if (measureCodepoints(ui, cps[0..draw_n]) > r.width and draw_n > 3) {
        while (draw_n > 3 and measureCodepoints(ui, cps[0 .. draw_n + 3]) > r.width) draw_n -= 1;
        cps[draw_n] = '.';
        cps[draw_n + 1] = '.';
        cps[draw_n + 2] = '.';
        draw_n += 3;
    }
    beginScissor(ui, rect(r.x, r.y - scale(ui, 2), r.width, r.height + scale(ui, 4)));
    defer rl.endScissorMode();
    const font_size = scale(ui, logical_font_size);
    const y = r.y + @max(0, (r.height - font_size) * 0.5) - scale(ui, 2);
    const position = vec(snapToPhysicalPixel(ui, r.x), snapToPhysicalPixel(ui, y));
    rl.drawTextCodepoints(ui.font, cps[0..draw_n], position, font_size, scale(ui, 1), color);
}

fn measureText(ui: *UiState, text: []const u8, max_width: f32) f32 {
    var cps: [512]i32 = undefined;
    var n = textToCodepoints(text, &cps);
    while (n > 0 and measureCodepoints(ui, cps[0..n]) > max_width) n -= 1;
    return measureCodepoints(ui, cps[0..n]);
}

fn measureCodepoints(ui: *UiState, cps: []const i32) f32 {
    if (cps.len == 0) return 0;
    return rl.measureTextCodepoints(ui.font, cps, @intCast(cps.len), scale(ui, logical_font_size), scale(ui, 1)).x;
}

fn textToCodepoints(text: []const u8, out: []i32) usize {
    var view = std.unicode.Utf8View.init(text) catch return asciiFallback(text, out);
    var it = view.iterator();
    var i: usize = 0;
    while (it.nextCodepoint()) |cp| {
        if (i >= out.len) break;
        out[i] = @intCast(cp);
        i += 1;
    }
    return i;
}

fn asciiFallback(text: []const u8, out: []i32) usize {
    const n = @min(text.len, out.len);
    for (text[0..n], 0..) |ch, i| out[i] = ch;
    return n;
}

fn rowMatches(ui: *UiState, row: worker.Row) bool {
    const needle = ui.search_buf[0..ui.search_len];
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
    var out = try formatRows(ui, include_path);
    defer out.deinit(ui.allocator);
    const z = try ui.allocator.dupeZ(u8, out.items);
    defer ui.allocator.free(z);
    rl.setClipboardText(z);
}

fn saveRows(ui: *UiState, include_path: bool) !void {
    const path = try showSaveDialog(ui);
    defer ui.allocator.free(path);
    if (path.len == 0) return;

    var out = try formatRows(ui, include_path);
    defer out.deinit(ui.allocator);
    var file = try std.Io.Dir.createFileAbsolute(ui.io, path, .{ .truncate = true });
    defer file.close(ui.io);
    var buffer: [4096]u8 = undefined;
    var writer = file.writer(ui.io, &buffer);
    try writer.interface.writeAll("\xEF\xBB\xBF");
    try writer.interface.writeAll(out.items);
    try writer.interface.flush();
}

fn showSaveDialog(ui: *UiState) ![]u8 {
    if (@import("builtin").os.tag != .windows) return ui.allocator.dupe(u8, "");
    var file_buf: [std.fs.max_path_bytes]u16 = @splat(0);
    const default_name = std.unicode.utf8ToUtf16LeStringLiteral("哈希校验结果.txt");
    @memcpy(file_buf[0..default_name.len], default_name);

    const filter = std.unicode.utf8ToUtf16LeStringLiteral("Text Files (*.txt)\x00*.txt\x00All Files (*.*)\x00*.*\x00");
    const title = std.unicode.utf8ToUtf16LeStringLiteral("保存结果");
    const def_ext = std.unicode.utf8ToUtf16LeStringLiteral("txt");
    var ofn = OpenFileNameW{
        .lStructSize = @sizeOf(OpenFileNameW),
        .lpstrFilter = filter.ptr,
        .lpstrFile = @ptrCast(&file_buf),
        .nMaxFile = file_buf.len,
        .lpstrTitle = title.ptr,
        .Flags = 0x00000002 | 0x00000004 | 0x00000800 | 0x00000008,
        .lpstrDefExt = def_ext.ptr,
    };
    if (!GetSaveFileNameW(&ofn)) return ui.allocator.dupe(u8, "");
    const len = std.mem.indexOfScalar(u16, &file_buf, 0) orelse file_buf.len;
    return std.unicode.utf16LeToUtf8Alloc(ui.allocator, file_buf[0..len]);
}

fn formatRows(ui: *UiState, include_path: bool) !std.ArrayList(u8) {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(ui.allocator);
    try out.appendSlice(ui.allocator, "文件\t大小");
    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();
    for (hash.all_algorithms) |algorithm| {
        if (ui.app.options.enabled(algorithm)) try out.print(ui.allocator, "\t{s}", .{algorithm.label()});
    }
    if (include_path) try out.appendSlice(ui.allocator, "\t完整路径");
    try out.append(ui.allocator, '\n');

    for (ui.app.rows.items) |row| {
        if (!rowMatches(ui, row)) continue;
        try out.print(ui.allocator, "{s}\t{s}", .{ row.file.name, row.file.size_label });
        for (hash.all_algorithms) |algorithm| {
            if (!ui.app.options.enabled(algorithm)) continue;
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
    return out;
}

fn uppercaseInto(buf: []u8, value: []const u8) []const u8 {
    const len = @min(buf.len, value.len);
    for (value[0..len], 0..) |ch, i| buf[i] = std.ascii.toUpper(ch);
    return buf[0..len];
}

fn algorithmLabelZ(algorithm: hash.Algorithm) [:0]const u8 {
    return algorithm_labels_z[@intFromEnum(algorithm)];
}

fn currentFilterLabel(ui: *const UiState) []const u8 {
    const index: usize = @intCast(std.math.clamp(ui.filter_column, 0, @as(i32, @intCast(filter_labels.len - 1))));
    return filter_labels[index];
}

fn rect(x: f32, y: f32, w: f32, h: f32) Rect {
    return .{ .x = x, .y = y, .width = w, .height = h };
}

fn vec(x: f32, y: f32) Vec2 {
    return .{ .x = x, .y = y };
}
