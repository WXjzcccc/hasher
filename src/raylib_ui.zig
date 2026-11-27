const std = @import("std");
const rl = @import("raylib");

const hash = @import("hash/core.zig");
const worker = @import("worker.zig");
const font_atlas = @import("font_atlas.zig");
const embedded_assets = @import("embedded_assets");
const context_menu = @import("context_menu.zig");
const single_instance = @import("single_instance.zig");
const windows_frame = @import("windows_frame.zig");
const lucide = @import("lucide_atlas.zig");

extern "comdlg32" fn GetSaveFileNameW(ofn: *OpenFileNameW) callconv(.winapi) bool;

extern "user32" fn OpenClipboard(hwnd: ?*anyopaque) callconv(.winapi) bool;
extern "user32" fn CloseClipboard() callconv(.winapi) bool;
extern "user32" fn GetClipboardData(format: u32) callconv(.winapi) ?*anyopaque;
extern "user32" fn IsClipboardFormatAvailable(format: u32) callconv(.winapi) bool;
extern "kernel32" fn GlobalLock(mem: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(mem: ?*anyopaque) callconv(.winapi) bool;

const cf_unicode_text: u32 = 13;

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
const column_count: usize = 12;

const layout = struct {
    const pad: f32 = 12;
    const title_h: f32 = 40;
    const toolbar_h: f32 = 36;
    const option_h: f32 = 28;
    const status_h: f32 = 46;
    const row_h: f32 = 30;
    const header_h: f32 = 34;
    const gap: f32 = 8;
    const card_radius: f32 = 10;
    const button_radius: f32 = 7;
};

const colors = struct {
    const bg = Color.init(10, 13, 17, 255);
    const bg_top = Color.init(17, 22, 29, 255);
    const panel = Color.init(17, 22, 29, 255);
    const panel2 = Color.init(23, 30, 39, 255);
    const elevated = Color.init(30, 39, 50, 255);
    const border = Color.init(38, 48, 61, 255);
    const border_strong = Color.init(58, 74, 94, 255);
    const text = Color.init(231, 238, 246, 255);
    const muted = Color.init(140, 152, 167, 255);
    const faint = Color.init(98, 110, 124, 255);
    const button = Color.init(26, 34, 44, 255);
    const button_hover = Color.init(36, 47, 60, 255);
    const button_down = Color.init(20, 27, 35, 255);
    const button_disabled = Color.init(21, 26, 33, 255);
    const accent = Color.init(62, 140, 246, 255);
    const accent_hover = Color.init(96, 165, 255, 255);
    const accent_down = Color.init(44, 114, 214, 255);
    const danger = Color.init(226, 84, 84, 255);
    const danger_hover = Color.init(244, 104, 104, 255);
    const danger_down = Color.init(196, 62, 62, 255);
    const close_hover = Color.init(232, 17, 35, 255);
    const close_down = Color.init(196, 13, 29, 255);
    const hash_value = Color.init(118, 208, 226, 255);
    const success = Color.init(64, 196, 140, 255);
    const warning = Color.init(226, 168, 74, 255);
    const path = Color.init(150, 163, 178, 255);
    const row_alt = Color.init(20, 26, 33, 255);
    const row_hover = Color.init(29, 39, 50, 255);
    const selected = Color.init(46, 96, 148, 255);
    const input = Color.init(14, 19, 25, 255);
    const scrollbar_track = Color.init(255, 255, 255, 10);
    const scrollbar_thumb = Color.init(88, 102, 118, 255);
};

const ButtonKind = enum { normal, primary, danger };

const ButtonVisual = struct {
    clicked: bool,
    hovered: bool,
    pressed: bool,
    hover_t: f32,
    lift: f32,
};

const RowFx = struct {
    appear: f32 = 0,
    born: f64 = 0,
    pulse: f32 = 0,
    status_hash: u64 = 0,
    seen: bool = false,
};

const ColumnDrop = struct {
    target: usize,
    before: bool,
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
    font_codepoint_count: usize = 0,
    /// Ink band of the loaded atlas, in drawing pixels, measured from the line
    /// origin raylib passes to drawTextCodepoints. Used for vertical centering
    /// so labels sit optically centered instead of on a guessed fudge factor.
    font_ink_top: f32 = 0,
    font_ink_height: f32 = 16,
    drawn_codepoints: std.AutoHashMap(i32, void),
    app_icon: rl.Texture2D = undefined,
    app_icon_loaded: bool = false,
    lucide_atlas: ?lucide.Atlas = null,
    render_scale: f32 = 1.0,
    dt: f32 = 1.0 / 60.0,
    now: f64 = 0,
    intro_anim: f32 = 0,
    hover_anims: std.AutoHashMap(u64, f32),
    row_fx: std.ArrayList(RowFx) = .empty,
    progress_anim: f32 = 0,
    progress_tint: Color = Color.init(62, 140, 246, 255),
    scroll_target_x: f32 = 0,
    scroll_target_y: f32 = 0,
    table_body: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    filter_anim: f32 = 0,
    checkbox_anim: [hash.algorithm_count]f32 = @splat(0),
    uppercase_anim: f32 = 0,
    search_focus_anim: f32 = 0,
    empty_anim: f32 = 0,
    toast_start: f64 = 0,
    toast_duration: f64 = 0,
    filter_column: i32 = @backingInt(FilterColumn.all),
    filter_open: bool = false,
    filter_button_rect: Rect = .{ .x = 0, .y = 0, .width = 0, .height = 0 },
    search_buf: [512:0]u8 = @splat(0),
    search_len: usize = 0,
    clipboard_buf: [2048]u8 = @splat(0),
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
    resize_start_x: f32 = 0,
    resize_start_width: f32 = 0,
    column_order: [12]usize = defaultColumnOrder(),
    dragging_column: ?usize = null,
    drag_start_x: f32 = 0,
    drag_moved: bool = false,
    selected_row: ?usize = null,
    selected_column: ?usize = null,
    rounded_frame_width: i32 = 0,
    rounded_frame_height: i32 = 0,
    rounded_frame_maximized: bool = false,
    context_menu_enabled: bool = false,
    context_queue: *single_instance.RequestQueue,
    current_cursor: rl.MouseCursor = .default,
    requested_cursor: rl.MouseCursor = .default,
    window_resize: ?windows_frame.ResizeSession = null,
    pointer_blocked: bool = false,
    last_cell_click_time: f64 = -1,
    last_cell_click_row: ?usize = null,
    last_cell_click_column: ?usize = null,
    toast_until: f64 = 0,
    toast_text: []const u8 = "",

    fn init(allocator: std.mem.Allocator, io: std.Io, context_queue: *single_instance.RequestQueue) !UiState {
        return .{
            .allocator = allocator,
            .io = io,
            .app = try worker.AppState.init(allocator, io),
            .drawn_codepoints = std.AutoHashMap(i32, void).init(allocator),
            .hover_anims = std.AutoHashMap(u64, f32).init(allocator),
            .context_queue = context_queue,
        };
    }

    fn deinit(self: *UiState) void {
        if (self.app_icon_loaded) rl.unloadTexture(self.app_icon);
        if (self.lucide_atlas) |*atlas| atlas.deinit();
        if (self.font_loaded) rl.unloadFont(self.font);
        self.allocator.free(self.font_codepoints);
        self.drawn_codepoints.deinit();
        self.hover_anims.deinit();
        self.row_fx.deinit(self.allocator);
        self.app.deinit();
    }
};

fn defaultColumnWidths() [12]f32 {
    return .{ 180, 126, 170, 170, 170, 170, 170, 170, 170, 170, 92, 380 };
}

fn defaultColumnOrder() [12]usize {
    return .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
}

const ui_text_samples = [_][]const u8{
    "Hasher",
    "1.6",
    "开始",
    "停止",
    "清空",
    "复制",
    "保存",
    "复制无路径",
    "保存无路径",
    "重置",
    "搜索",
    "算法",
    "大写",
    "文件",
    "大小",
    "状态",
    "完整路径",
    "在计算完毕后可直接双击单元格复制",
    "拖入文件或文件夹",
    "或点击开始按钮计算哈希",
    "没有匹配的结果",
    "就绪",
    "计算中",
    "已复制到剪贴板",
    "已清空",
    "已停止",
    "完成",
    "排队中",
    "等待中",
    "错误",
    "开启右键菜单",
    "关闭右键菜单",
    "右键菜单",
};

fn approach(value: f32, target: f32, speed: f32, dt: f32) f32 {
    const amount = 1.0 - std.math.exp(-speed * dt);
    const next = value + (target - value) * amount;
    return if (@abs(target - next) < 0.0008) target else next;
}

fn easeOutCubic(t: f32) f32 {
    const clamped = std.math.clamp(t, 0, 1);
    const remaining = 1.0 - clamped;
    return 1.0 - remaining * remaining * remaining;
}

/// Smoothly animates a widget-owned value. The id must stay stable between
/// frames (derive it from the layout rect, not from the mouse position).
fn anim(ui: *UiState, id: u64, target: f32, speed: f32) f32 {
    if (ui.hover_anims.count() > 4096) ui.hover_anims.clearRetainingCapacity();
    const entry = ui.hover_anims.getOrPut(id) catch return target;
    if (!entry.found_existing) entry.value_ptr.* = target;
    entry.value_ptr.* = approach(entry.value_ptr.*, target, speed, ui.dt);
    return entry.value_ptr.*;
}

fn widgetId(salt: u64, r: Rect) u64 {
    var hasher = std.hash.Wyhash.init(salt);
    hasher.update(std.mem.asBytes(&r.x));
    hasher.update(std.mem.asBytes(&r.y));
    hasher.update(std.mem.asBytes(&r.width));
    hasher.update(std.mem.asBytes(&r.height));
    return hasher.final();
}

/// Radius is given in logical pixels; raylib expects a roundness factor.
fn roundnessFor(r: Rect, radius: f32) f32 {
    const min_side = @min(r.width, r.height);
    if (min_side <= 0) return 0;
    return std.math.clamp(radius * 2.0 / min_side, 0, 1);
}

fn rrect(r: Rect, radius: f32, color: Color) void {
    if (r.width <= 0 or r.height <= 0) return;
    if (radius <= 0.5) return rl.drawRectangleRec(r, color);
    const segments: i32 = @intFromFloat(std.math.clamp(radius * 2.0, 4, 24));
    rl.drawRectangleRounded(r, roundnessFor(r, radius), segments, color);
}

fn rrectLines(r: Rect, radius: f32, thick: f32, color: Color) void {
    if (r.width <= 1 or r.height <= 1) return;
    const segments: i32 = @intFromFloat(std.math.clamp(radius * 2.0, 4, 24));
    rl.drawRectangleRoundedLinesEx(r, roundnessFor(r, radius), segments, thick, color);
}

fn drawShadow(r: Rect, radius: f32, strength: u8) void {
    if (strength == 0) return;
    rl.drawRectangleRounded(rect(r.x, r.y + 4, r.width, r.height), roundnessFor(r, radius), 12, Color.init(0, 0, 0, strength / 2));
    rl.drawRectangleRounded(rect(r.x, r.y + 2, r.width, r.height), roundnessFor(r, radius), 12, Color.init(0, 0, 0, strength));
}

fn drawDot(center: Vec2, radius: f32, color: Color) void {
    rl.drawCircleV(center, radius, color);
}

pub fn run(allocator: std.mem.Allocator, io: std.Io, context_request: ?context_menu.ContextHashRequest, context_queue: *single_instance.RequestQueue) !void {
    rl.setConfigFlags(.{
        .window_resizable = true,
        .window_undecorated = true,
        .window_highdpi = true,
        .msaa_4x_hint = true,
        .vsync_hint = true,
    });
    rl.initWindow(1180, 760, single_instance.window_title);
    defer rl.closeWindow();
    windows_frame.installNativeFrame(rl.getWindowHandle());
    setAppIcon();
    rl.setExitKey(.null);
    rl.setTargetFPS(60);

    var ui = try UiState.init(allocator, io, context_queue);
    defer ui.deinit();
    windows_frame.setCopyDataHandler(ui.context_queue, single_instance.handleCopyData);
    defer windows_frame.setCopyDataHandler(null, null);
    ui.context_menu_enabled = context_menu.isInstalled(allocator);
    if (ui.context_menu_enabled) context_menu.install(allocator) catch {};
    updateScale(&ui);
    updateWindowFrame(&ui);
    loadAppIconTexture(&ui);
    ui.lucide_atlas = lucide.Atlas.init(embedded_assets.lucide_icons_png) catch null;
    try loadFont(&ui);
    rl.setWindowMinSize(820, 520);
    if (context_request) |request| ui.context_queue.enqueueRequest(request);

    while (!rl.windowShouldClose()) {
        beginCursorFrame(&ui);
        ui.now = rl.getTime();
        ui.dt = std.math.clamp(rl.getFrameTime(), 1.0 / 240.0, 0.05);
        ui.intro_anim = approach(ui.intro_anim, 1, 9, ui.dt);
        updateScale(&ui);
        updateWindowFrame(&ui);
        handleDrops(&ui);
        handleShortcuts(&ui);
        ui.context_queue.startIfReady(&ui.app, ui.now);
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
    ui.font_codepoints = try buildFontCodepoints(ui);
    ui.font = loadFontAtlas(ui, ui.font_codepoints) catch {
        ui.font = try rl.getFontDefault();
        applyFontMetrics(ui, ui.font);
        ui.font_render_scale = ui.render_scale;
        ui.font_codepoint_count = ui.drawn_codepoints.count();
        return;
    };
    ui.font_loaded = true;
    ui.font_render_scale = ui.render_scale;
    ui.font_codepoint_count = ui.drawn_codepoints.count();
}

/// Rebuilds the glyph atlas only when genuinely new codepoints appear (or the
/// display scale changes), instead of on every row status update. Rebuilding is
/// expensive, so tying it to text changes made the table stutter while hashing.
fn ensureFontCurrent(ui: *UiState) !void {
    const scale_changed = @abs(ui.font_render_scale - ui.render_scale) > 0.001;
    if (!scale_changed and ui.drawn_codepoints.count() == ui.font_codepoint_count) return;
    const next_codepoints = try buildFontCodepoints(ui);
    const next_font = loadFontAtlas(ui, next_codepoints) catch {
        ui.allocator.free(next_codepoints);
        ui.font_render_scale = ui.render_scale;
        ui.font_codepoint_count = ui.drawn_codepoints.count();
        return;
    };
    if (ui.font_loaded) rl.unloadFont(ui.font);
    ui.allocator.free(ui.font_codepoints);
    ui.font = next_font;
    ui.font_loaded = true;
    ui.font_codepoints = next_codepoints;
    ui.font_render_scale = ui.render_scale;
    ui.font_codepoint_count = ui.drawn_codepoints.count();
}

fn loadFontAtlas(ui: *UiState, codepoints: []const i32) !rl.Font {
    const pixel_size = @max(1, @as(i32, @intFromFloat(@ceil(pixelScale(ui, logical_font_size)))));
    const font = try font_atlas.load(embedded_assets.ttf, pixel_size, codepoints);
    if (!font.isReady()) return error.FontLoadFailed;
    rl.setTextureFilter(font.texture, .bilinear);
    applyFontMetrics(ui, font);
    return font;
}

/// Representative glyphs (Latin caps, digits, CJK ideographs) used to derive the
/// vertical ink band. Scanning the whole atlas is not an option - a few
/// outlier glyphs (full-width forms, unusual accents) would skew the band and
/// push every label off center.
const ink_sample_codepoints = [_]i32{ 'H', 'M', 'E', '0', '5', 0x4E2D, 0x6587, 0x56FD };

/// Records the vertical ink band of the atlas so text can be centered by what is
/// actually painted rather than by the em box. The band is derived from
/// representative glyphs, with glyph padding removed so transparent padding does
/// not inflate it; `font_ink_top` is the distance from the line origin raylib
/// receives to the top of the ink.
fn applyFontMetrics(ui: *UiState, font: rl.Font) void {
    const base: f32 = @floatFromInt(@max(1, font.baseSize));
    const k = logical_font_size / base;
    const count: usize = if (font.glyphCount > 0) @intCast(font.glyphCount) else 0;

    var top: f32 = std.math.floatMax(f32);
    var bottom: f32 = -std.math.floatMax(f32);
    for (ink_sample_codepoints) |cp| {
        var index: ?usize = null;
        for (0..count) |i| {
            if (font.glyphs[i].value == cp) {
                index = i;
                break;
            }
        }
        const i = index orelse continue;
        const height = font.recs[i].height;
        if (height <= 0) continue;
        const glyph_top = @as(f32, @floatFromInt(font.glyphs[i].offsetY));
        top = @min(top, glyph_top);
        bottom = @max(bottom, glyph_top + height);
    }

    if (bottom > top) {
        ui.font_ink_top = top * k;
        ui.font_ink_height = (bottom - top) * k;
    } else {
        // No sample glyph matched (unexpected charset): fall back to the em box
        // minus typical line gap so labels still sit close to centered.
        ui.font_ink_top = logical_font_size * 0.16;
        ui.font_ink_height = logical_font_size * 0.72;
    }
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
    for (ui_text_samples) |sample| try appendTextCodepoints(&codepoints, &seen, sample);
    for (filter_labels) |label| try appendTextCodepoints(&codepoints, &seen, label);
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
    while (it.nextCodepoint()) |cp| _ = try ui.drawn_codepoints.getOrPut(@intCast(cp));
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
    const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
    if (ctrl and rl.isKeyPressed(.v)) {
        appendSearchText(ui, clipboardText(ui) orelse "");
        return;
    }
    if ((rl.isKeyPressed(.backspace) or rl.isKeyPressedRepeat(.backspace)) and ui.search_len > 0) {
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

/// Appends pasted text, dropping control characters so a multi-line clipboard
/// payload still yields a usable single-line query.
fn appendSearchText(ui: *UiState, text: []const u8) void {
    for (text) |byte| {
        if (ui.search_len + 1 >= ui.search_buf.len) break;
        if (byte == '\r' or byte == '\n' or byte == '\t') continue;
        if (byte < 0x20) continue;
        ui.search_buf[ui.search_len] = byte;
        ui.search_len += 1;
    }
    ui.search_buf[ui.search_len] = 0;
}

fn clipboardText(ui: *UiState) ?[]const u8 {
    if (@import("builtin").os.tag != .windows) {
        const text = rl.getClipboardText();
        return if (text.len == 0) null else text;
    }
    if (!IsClipboardFormatAvailable(cf_unicode_text)) return null;
    if (!OpenClipboard(rl.getWindowHandle())) return null;
    defer _ = CloseClipboard();
    const handle = GetClipboardData(cf_unicode_text) orelse return null;
    const raw = GlobalLock(handle) orelse return null;
    defer _ = GlobalUnlock(handle);
    const wide: [*:0]const u16 = @ptrCast(@alignCast(raw));
    var wide_len: usize = 0;
    while (wide[wide_len] != 0) wide_len += 1;
    const written = std.unicode.utf16LeToUtf8(ui.clipboard_buf[0..], wide[0..wide_len]) catch return null;
    return ui.clipboard_buf[0..written];
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
    const in_title = mouse.y >= 0 and mouse.y <= scale(ui, layout.title_h) and mouse.x < screen_w - scale(ui, 138);
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
    if (ui.window_resize) |session| {
        setResizeCursor(ui, session.hit_test);
        if (rl.isMouseButtonDown(.left)) {
            const dpi = rl.getWindowScaleDPI();
            windows_frame.updateResize(
                rl.getWindowHandle(),
                session,
                @intFromFloat(820 * dpi.x),
                @intFromFloat(520 * dpi.y),
            );
        } else {
            windows_frame.endResize();
            ui.window_resize = null;
        }
        return;
    }

    const mouse = rl.getMousePosition();
    const hit = resizeHitTest(ui, mouse);
    if (hit) |ht| {
        setResizeCursor(ui, ht);
        if (@import("builtin").os.tag == .windows and rl.isMouseButtonPressed(.left)) {
            ui.window_resize = windows_frame.beginResize(rl.getWindowHandle(), ht);
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
    ui.pointer_blocked = ui.filter_open;
    drawBackdrop(ui, w, h);
    drawTitleBar(ui, w);

    const pad = scale(ui, layout.pad);
    const toolbar_top = scale(ui, layout.title_h) + pad * 0.75;
    const toolbar_bottom = drawToolbar(ui, rect(pad, toolbar_top, w - pad * 2, scale(ui, layout.toolbar_h)));
    const options_bottom = drawOptions(ui, pad, w - pad, toolbar_bottom + scale(ui, layout.gap));
    const status_top = options_bottom + scale(ui, layout.gap);
    const status = rect(pad, status_top, w - pad * 2, scale(ui, layout.status_h));
    drawStatus(ui, status);
    const table_top = status_top + status.height + scale(ui, layout.gap);
    drawTable(ui, rect(pad, table_top, w - pad * 2, h - table_top - pad));
    if (ui.filter_open or ui.filter_anim > 0.01) drawFilterPopup(ui);
    drawToast(ui, w, h);
    if (ui.intro_anim < 0.999) rl.drawRectangleRec(rect(0, 0, w, h), colors.bg.alpha(1 - ui.intro_anim));
}

fn drawBackdrop(ui: *UiState, w: f32, h: f32) void {
    _ = ui;
    rl.drawRectangleGradientV(0, 0, @intFromFloat(w), @intFromFloat(h), colors.bg_top, colors.bg);
    const radius = @max(w, h) * 0.62;
    rl.drawCircleGradient(vec(w * 0.22, -h * 0.18), radius, Color.init(62, 140, 246, 26), Color.init(62, 140, 246, 0));
    rl.drawCircleGradient(vec(w * 0.92, h * 0.02), radius * 0.7, Color.init(96, 165, 255, 14), Color.init(96, 165, 255, 0));
}

fn drawTitleBar(ui: *UiState, w: f32) void {
    const h = scale(ui, layout.title_h);
    rl.drawRectangleGradientV(0, 0, @intFromFloat(w), @intFromFloat(h), Color.init(23, 29, 38, 255), Color.init(15, 20, 26, 255));
    rl.drawRectangleRec(rect(0, h - 1, w, 1), colors.border.alpha(0.9));

    const icon_size = scale(ui, 20);
    const icon_x = scale(ui, layout.pad) + scale(ui, 2);
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
    const title_x = icon_x + icon_size + scale(ui, 10);
    drawTextClipped(ui, "Hasher", rect(title_x, 0, scale(ui, 140), h), colors.text);
    const title_w = measureText(ui, "Hasher", scale(ui, 200));
    const badge = rect(title_x + title_w + scale(ui, 8), (h - scale(ui, 18)) * 0.5, scale(ui, 36), scale(ui, 18));
    rrect(badge, scale(ui, 9), colors.accent.alpha(0.16));
    drawTextCentered(ui, "1.6", badge, colors.accent_hover);

    const button_w = scale(ui, 46);
    var x = w - button_w * 3;
    if (titleBarButton(ui, rect(x, 0, button_w, h), .minimize)) {
        if (@import("builtin").os.tag == .windows) windows_frame.minimize(rl.getWindowHandle()) else rl.minimizeWindow();
    }
    x += button_w;
    if (titleBarButton(ui, rect(x, 0, button_w, h), if (rl.isWindowMaximized()) .restore else .maximize)) {
        if (@import("builtin").os.tag == .windows) {
            windows_frame.toggleMaximize(rl.getWindowHandle(), rl.isWindowMaximized());
        } else if (rl.isWindowMaximized()) {
            rl.restoreWindow();
        } else {
            rl.maximizeWindow();
        }
    }
    x += button_w;
    if (titleBarButton(ui, rect(x, 0, button_w, h), .close)) {
        if (@import("builtin").os.tag == .windows) windows_frame.close(rl.getWindowHandle()) else rl.closeWindow();
    }
}

fn titleBarButton(ui: *UiState, r: Rect, icon: Icon) bool {
    const mouse = rl.getMousePosition();
    const hovered = rl.checkCollisionPointRec(mouse, r);
    const pressed = hovered and rl.isMouseButtonDown(.left);
    const is_close = icon == .close;
    const hover_t = anim(ui, widgetId(if (is_close) 0x9c10 else 0x9c11, r), if (hovered) 1 else 0, 20);
    const target = if (is_close)
        (if (pressed) colors.close_down else colors.close_hover)
    else
        (if (pressed) colors.button_down else colors.elevated);
    rl.drawRectangleRec(r, rl.colorLerp(Color.init(target.r, target.g, target.b, 0), target, hover_t));

    const icon_size = scale(ui, 14);
    const nudge = if (pressed) scale(ui, 0.6) else 0;
    const icon_rect = rect(
        snapToPhysicalPixel(ui, r.x + (r.width - icon_size) * 0.5),
        snapToPhysicalPixel(ui, r.y + (r.height - icon_size) * 0.5 + nudge),
        icon_size,
        icon_size,
    );
    const icon_color = rl.colorLerp(colors.muted, if (is_close) Color.init(255, 255, 255, 255) else colors.text, hover_t);
    drawIcon(ui, icon, icon_rect, icon_color);
    return hovered and rl.isMouseButtonReleased(.left);
}

fn buttonWidth(ui: *UiState, label: []const u8, min_width: f32) f32 {
    return @max(scale(ui, min_width), measureText(ui, label, scale(ui, 420)) + scale(ui, 46));
}

fn flowDivider(ui: *UiState, flow: *FlowLayout) void {
    const height = flow.item_height * 0.62;
    const x = flow.x + scale(ui, 3);
    rl.drawRectangleRec(rect(x, flow.y + (flow.item_height - height) * 0.5, 1, height), colors.border);
    flow.x += scale(ui, 12);
}

fn drawToolbar(ui: *UiState, area: Rect) f32 {
    worker.lockMutex(&ui.app.mutex);
    const processing = ui.app.processing;
    ui.app.mutex.unlock();

    const gap = scale(ui, 6);
    const row_h = scale(ui, 30);
    const filter_w = scale(ui, 108);
    const search_w = scale(ui, 214);
    const reset_w = scale(ui, 38);
    var right_x = area.x + area.width - (filter_w + search_w + reset_w + gap * 2);
    const filter_rect = rect(right_x, area.y, filter_w, row_h);
    right_x += filter_w + gap;
    const search_rect = rect(right_x, area.y, search_w, row_h);
    right_x += search_w + gap;
    const reset_rect = rect(right_x, area.y, reset_w, row_h);

    var flow = FlowLayout.init(area.x + scale(ui, 2), area.y, filter_rect.x - scale(ui, 10), row_h, gap, gap);
    if (toolButtonEx(ui, flow.next(buttonWidth(ui, "开始", 74)), .play, "开始", .primary, !processing, false)) ui.app.start() catch {};
    if (toolButtonEx(ui, flow.next(buttonWidth(ui, "停止", 74)), .stop, "停止", .danger, processing, processing)) ui.app.stop();
    if (toolButtonEx(ui, flow.next(buttonWidth(ui, "清空", 74)), .clear, "清空", .normal, !processing, false)) ui.app.clear();
    flowDivider(ui, &flow);
    if (toolButtonEx(ui, flow.next(buttonWidth(ui, "复制", 72)), .copy, "复制", .normal, true, false)) copyRows(ui, true) catch {};
    if (toolButtonEx(ui, flow.next(buttonWidth(ui, "保存", 72)), .save, "保存", .normal, true, false)) saveRows(ui, true) catch {};
    if (toolButtonEx(ui, flow.next(buttonWidth(ui, "复制无路径", 108)), .copy_no_path, "复制无路径", .normal, true, false)) copyRows(ui, false) catch {};
    if (toolButtonEx(ui, flow.next(buttonWidth(ui, "保存无路径", 108)), .save_no_path, "保存无路径", .normal, true, false)) saveRows(ui, false) catch {};

    ui.filter_button_rect = filter_rect;
    if (filterButton(ui, filter_rect)) ui.filter_open = !ui.filter_open;
    drawSearch(ui, search_rect);
    if (toolButtonEx(ui, reset_rect, .reset, "", .normal, true, false)) {
        @memset(&ui.search_buf, 0);
        ui.search_len = 0;
    }
    return @max(flow.bottom(), area.y + row_h);
}

fn drawOptions(ui: *UiState, left: f32, right: f32, start_y: f32) f32 {
    const row_h = scale(ui, layout.option_h);
    const gap = scale(ui, 6);

    var right_cursor = right;
    const settings_label = if (ui.context_menu_enabled) "关闭右键菜单" else "开启右键菜单";
    const settings_w = buttonWidth(ui, settings_label, 112);
    const settings_rect = rect(right_cursor - settings_w, start_y, settings_w, row_h);
    right_cursor -= settings_w + gap;
    const upper_w = scale(ui, 68);
    const upper_rect = rect(right_cursor - upper_w, start_y, upper_w, row_h);
    right_cursor -= upper_w;

    worker.lockMutex(&ui.app.mutex);
    var flow = FlowLayout.init(left, start_y, right_cursor - scale(ui, 10), row_h, gap, scale(ui, 4));
    for (hash.all_algorithms) |algorithm| {
        const label = algorithmLabelZ(algorithm);
        const index = @backingInt(algorithm);
        const chip_w = @max(scale(ui, 62), measureText(ui, label, scale(ui, 300)) + scale(ui, 42));
        const chip = flow.next(chip_w);
        const target: f32 = if (ui.app.options.enabled(algorithm)) 1 else 0;
        ui.checkbox_anim[index] = approach(ui.checkbox_anim[index], target, 16, ui.dt);
        if (optionChip(ui, chip, label, ui.checkbox_anim[index])) {
            ui.app.options.set(algorithm, !ui.app.options.enabled(algorithm));
        }
    }
    const uppercase_target: f32 = if (ui.app.uppercase) 1 else 0;
    ui.uppercase_anim = approach(ui.uppercase_anim, uppercase_target, 16, ui.dt);
    if (optionChip(ui, upper_rect, "大写", ui.uppercase_anim)) ui.app.uppercase = !ui.app.uppercase;
    const context_enabled = ui.context_menu_enabled;
    ui.app.mutex.unlock();

    const settings_toggle = if (context_enabled) "关闭右键菜单" else "开启右键菜单";
    if (toolButtonEx(ui, settings_rect, .settings, settings_toggle, .normal, true, context_enabled)) configureContextMenu(ui);
    return flow.bottom();
}

fn drawStatus(ui: *UiState, area: Rect) void {
    var message_buf: [160]u8 = undefined;
    var count_buf: [64]u8 = undefined;
    worker.lockMutex(&ui.app.mutex);
    const done = ui.app.progress_done;
    const total = ui.app.progress_total;
    const processing = ui.app.processing;
    const message = copyTruncated(&message_buf, ui.app.status_message);
    ui.app.mutex.unlock();

    const color = progressColor(message, processing, done, total);
    const ratio: f32 = if (total == 0) 0 else @as(f32, @floatFromInt(@min(done, total))) / @as(f32, @floatFromInt(total));
    ui.progress_anim = approach(ui.progress_anim, ratio, 7, ui.dt);
    ui.progress_tint = rl.colorLerp(ui.progress_tint, color, 1.0 - std.math.exp(-10.0 * ui.dt));

    drawShadow(area, scale(ui, layout.card_radius), 56);
    rrect(area, scale(ui, layout.card_radius), colors.panel);
    rrectLines(area, scale(ui, layout.card_radius), 1, colors.border);

    const pulse: f32 = if (processing) 1.0 + 0.35 * @sin(@as(f32, @floatCast(ui.now)) * 5.0) else 1.0;
    const dot_center = vec(area.x + scale(ui, 17), area.y + scale(ui, 17));
    if (processing) drawDot(dot_center, scale(ui, 9) * pulse, ui.progress_tint.alpha(0.14));
    drawDot(dot_center, scale(ui, 3.6), ui.progress_tint);
    drawTextClipped(ui, message, rect(dot_center.x + scale(ui, 11), area.y + scale(ui, 5), @max(scale(ui, 80), area.width * 0.5), scale(ui, 22)), colors.text);

    const percent = @round(ui.progress_anim * 100.0);
    const counts = std.fmt.bufPrint(&count_buf, "{d} / {d}  ·  {d:.0}%", .{ done, total, percent }) catch "";
    const counts_w = measureText(ui, counts, scale(ui, 260));
    drawTextClipped(ui, counts, rect(area.x + area.width - counts_w - scale(ui, 14), area.y + scale(ui, 5), counts_w + scale(ui, 2), scale(ui, 22)), colors.muted);

    const bar = rect(area.x + scale(ui, 14), area.y + area.height - scale(ui, 15), area.width - scale(ui, 28), scale(ui, 6));
    rrect(bar, scale(ui, 3), Color.init(255, 255, 255, 16));
    const fill_w = bar.width * std.math.clamp(ui.progress_anim, 0, 1);
    if (fill_w > 0.5) {
        const fill = rect(bar.x, bar.y, fill_w, bar.height);
        rrect(fill, scale(ui, 3), ui.progress_tint);
        rl.drawRectangleRec(rect(fill.x + scale(ui, 2), fill.y + 1, @max(0, fill.width - scale(ui, 4)), 1), Color.init(255, 255, 255, 46));
        if (processing) drawShimmer(ui, fill);
    }
}

fn drawShimmer(ui: *UiState, fill: Rect) void {
    const band_w = @max(scale(ui, 70), fill.width * 0.22);
    const cycle = 1.7;
    const phase = @mod(@as(f32, @floatCast(ui.now)), cycle) / cycle;
    const x = fill.x - band_w + (fill.width + band_w) * phase;
    const half = band_w * 0.5;
    beginScissor(ui, fill);
    defer rl.endScissorMode();
    const soft = Color.init(255, 255, 255, 58);
    const clear = Color.init(255, 255, 255, 0);
    const y: i32 = @intFromFloat(fill.y);
    const h: i32 = @intFromFloat(fill.height);
    rl.drawRectangleGradientH(@intFromFloat(x), y, @intFromFloat(half), h, clear, soft);
    rl.drawRectangleGradientH(@intFromFloat(x + half), y, @intFromFloat(half), h, soft, clear);
}

fn copyTruncated(buf: []u8, text: []const u8) []const u8 {
    if (text.len <= buf.len) {
        @memcpy(buf[0..text.len], text);
        return buf[0..text.len];
    }
    var len = buf.len;
    while (len > 0 and (text[len] & 0b1100_0000) == 0b1000_0000) len -= 1;
    @memcpy(buf[0..len], text[0..len]);
    return buf[0..len];
}

fn progressColor(status: []const u8, processing: bool, done: usize, total: usize) Color {
    if (std.mem.indexOf(u8, status, "错误") != null or std.mem.indexOf(u8, status, "失败") != null) return colors.danger;
    if (std.mem.indexOf(u8, status, "停止") != null) return colors.warning;
    if (!processing and total > 0 and done >= total) return colors.success;
    return colors.accent;
}

fn drawTable(ui: *UiState, area: Rect) void {
    const scrollbar_size = scale(ui, 10);
    const row_h = scale(ui, layout.row_h);
    const header_h = scale(ui, layout.header_h);
    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();

    const body = rect(area.x, area.y + header_h, area.width, area.height - header_h - scrollbar_size);
    ui.table_body = body;

    var visible_count: usize = 0;
    for (ui.app.rows.items) |row| {
        if (rowMatches(ui, row)) visible_count += 1;
    }
    const content_h = @as(f32, @floatFromInt(visible_count)) * row_h;
    const has_vertical = content_h > body.height + 0.5;
    const viewport_w = area.width - (if (has_vertical) scrollbar_size else 0);
    const content_w = totalTableWidth(ui, ui.app.options, viewport_w);
    syncRowEffects(ui);

    drawShadow(area, scale(ui, layout.card_radius), 64);
    rrect(area, scale(ui, layout.card_radius), colors.panel);
    handleTableScroll(ui, rect(body.x, body.y, viewport_w, body.height), content_w, content_h);

    if (visible_count == 0) {
        drawTableEmpty(ui, body);
    } else {
        ui.empty_anim = 0;
        beginScissor(ui, body);
        defer rl.endScissorMode();
        var visible_index: usize = 0;
        for (ui.app.rows.items, 0..) |row, row_index| {
            if (!rowMatches(ui, row)) continue;
            const row_y = body.y + @as(f32, @floatFromInt(visible_index)) * row_h - ui.table_scroll_y;
            if (row_y + row_h >= body.y - row_h and row_y <= body.y + body.height) {
                drawRow(ui, row, area.x - ui.table_scroll_x, row_y, row_h, visible_index, row_index, ui.app.options, viewport_w);
            }
            visible_index += 1;
        }
    }

    drawTableHeader(ui, area.x, area.y, area.width, header_h, ui.app.options, viewport_w);
    if (content_w > viewport_w + 0.5) {
        const fade_w = scale(ui, 28);
        beginScissor(ui, body);
        defer rl.endScissorMode();
        if (ui.table_scroll_x > 0.5) {
            rl.drawRectangleGradientH(@intFromFloat(body.x), @intFromFloat(body.y), @intFromFloat(fade_w), @intFromFloat(body.height), colors.panel.alpha(0.92), colors.panel.alpha(0));
        }
        if (ui.table_scroll_x < content_w - viewport_w - 0.5) {
            rl.drawRectangleGradientH(@intFromFloat(body.x + body.width - fade_w), @intFromFloat(body.y), @intFromFloat(fade_w), @intFromFloat(body.height), colors.panel.alpha(0), colors.panel.alpha(0.92));
        }
    }
    const hbar_w = area.width - (if (has_vertical) scrollbar_size else 0);
    drawHorizontalScroll(ui, rect(area.x, area.y + area.height - scrollbar_size, hbar_w, scrollbar_size), content_w, viewport_w);
    drawVerticalScroll(ui, rect(area.x + area.width - scrollbar_size, body.y, scrollbar_size, body.height), content_h);
    rrectLines(area, scale(ui, layout.card_radius), 1, colors.border);
}

fn hashText(text: []const u8) u64 {
    return std.hash.Wyhash.hash(0x5eed, text);
}

/// Keeps the per-row animation state in sync with the worker's row list:
/// newly added rows get a staggered entrance, completed rows get one pulse.
fn syncRowEffects(ui: *UiState) void {
    const rows = ui.app.rows.items;
    if (ui.row_fx.items.len > rows.len) {
        ui.row_fx.shrinkRetainingCapacity(rows.len);
        if (rows.len == 0) {
            ui.selected_row = null;
            ui.selected_column = null;
            ui.scroll_target_x = 0;
            ui.scroll_target_y = 0;
            ui.empty_anim = 0;
        }
    } else if (ui.row_fx.items.len < rows.len) {
        const previous_len = ui.row_fx.items.len;
        var index = previous_len;
        while (index < rows.len) : (index += 1) {
            const stagger = @min(index - previous_len, 22);
            const delay = @as(f64, @floatFromInt(stagger)) * 0.016;
            ui.row_fx.append(ui.allocator, .{ .born = ui.now + delay }) catch return;
        }
    }

    for (rows, 0..) |row, index| {
        if (index >= ui.row_fx.items.len) break;
        const fx = &ui.row_fx.items[index];
        const target: f32 = if (ui.now >= fx.born) 1 else 0;
        fx.appear = approach(fx.appear, target, 13, ui.dt);
        fx.pulse = approach(fx.pulse, 0, 4.2, ui.dt);
        const digest = hashText(row.status);
        if (!fx.seen) {
            fx.seen = true;
            fx.status_hash = digest;
        } else if (digest != fx.status_hash) {
            fx.status_hash = digest;
            if (std.mem.eql(u8, row.status, "完成") or std.mem.indexOf(u8, row.status, "错误") != null) fx.pulse = 1;
        }
    }
}

fn drawTableEmpty(ui: *UiState, body: Rect) void {
    ui.empty_anim = approach(ui.empty_anim, 1, 8, ui.dt);
    const pulse = 0.5 + 0.5 * @sin(@as(f32, @floatCast(ui.now)) * 1.6);
    const has_filter = ui.search_len > 0 or ui.filter_column != @backingInt(FilterColumn.all);
    const title = if (has_filter) "没有匹配的结果" else "拖入文件或文件夹";
    const hint = if (has_filter) "试试清空搜索条件或切换筛选列" else "或点击开始按钮计算哈希";
    const center = vec(body.x + body.width * 0.5, body.y + body.height * 0.46);
    const ring = scale(ui, 42);
    rl.drawCircleV(center, ring + scale(ui, 10) * pulse, Color.init(62, 140, 246, 8));
    rl.drawCircleV(center, ring, Color.init(62, 140, 246, 16));
    rl.drawRing(center, ring - scale(ui, 0.8), ring + scale(ui, 0.8), 0, 360, 64, colors.accent.alpha(0.30 + 0.16 * pulse));
    rl.drawLineEx(vec(center.x - scale(ui, 11), center.y), vec(center.x + scale(ui, 11), center.y), scale(ui, 2), colors.accent.alpha(0.85));
    rl.drawLineEx(vec(center.x, center.y - scale(ui, 11)), vec(center.x, center.y + scale(ui, 11)), scale(ui, 2), colors.accent.alpha(0.85));

    const title_w = measureText(ui, title, body.width * 0.8);
    drawTextCentered(ui, title, rect(center.x - title_w * 0.5, center.y + ring + scale(ui, 16), title_w + scale(ui, 2), scale(ui, 24)), colors.text.alpha(ui.empty_anim));
    const hint_w = measureText(ui, hint, body.width * 0.8);
    drawTextCentered(ui, hint, rect(center.x - hint_w * 0.5, center.y + ring + scale(ui, 44), hint_w + scale(ui, 2), scale(ui, 20)), colors.faint.alpha(ui.empty_anim));
}

fn handleTableScroll(ui: *UiState, area: Rect, content_w: f32, content_h: f32) void {
    const max_x = @max(0, content_w - area.width);
    const max_y = @max(0, content_h - area.height);
    if (!ui.pointer_blocked and rl.checkCollisionPointRec(rl.getMousePosition(), area)) {
        const wheel = rl.getMouseWheelMoveV();
        if (wheel.y != 0) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                ui.scroll_target_x -= wheel.y * scale(ui, 68);
            } else {
                ui.scroll_target_y -= wheel.y * scale(ui, 68);
            }
        }
    }
    ui.scroll_target_x = std.math.clamp(ui.scroll_target_x, 0, max_x);
    ui.scroll_target_y = std.math.clamp(ui.scroll_target_y, 0, max_y);
    ui.table_scroll_x = approach(ui.table_scroll_x, ui.scroll_target_x, 20, ui.dt);
    ui.table_scroll_y = approach(ui.table_scroll_y, ui.scroll_target_y, 20, ui.dt);
    if (@abs(ui.table_scroll_x - ui.scroll_target_x) < 0.4) ui.table_scroll_x = ui.scroll_target_x;
    if (@abs(ui.table_scroll_y - ui.scroll_target_y) < 0.4) ui.table_scroll_y = ui.scroll_target_y;
}

fn drawTableHeader(ui: *UiState, x: f32, y: f32, width: f32, h: f32, options: hash.HashOptions, layout_w: f32) void {
    const radius = scale(ui, layout.card_radius);
    rrect(rect(x, y, width, h), radius, colors.panel2);
    rl.drawRectangleRec(rect(x, y + h - radius * 0.5, width, radius * 0.5), colors.panel2);
    rl.drawRectangleRec(rect(x, y + h - 1, width, 1), colors.border);

    if (!rl.isMouseButtonDown(.left)) {
        ui.resizing_column = null;
        ui.dragging_column = null;
        ui.drag_moved = false;
    }
    if (ui.dragging_column != null) requestCursor(ui, .resize_all);

    var col_x = x - ui.table_scroll_x;
    var pending_drop: ?ColumnDrop = null;
    for (ui.column_order) |column| {
        if (!isColumnVisible(options, column)) continue;
        const sw = columnWidth(ui, options, column, layout_w);
        if (pushHeaderWidth(ui, &col_x, y, h, column, columnLabel(column), sw)) |drop| {
            pending_drop = drop;
        }
    }

    if (pending_drop) |drop| {
        if (ui.dragging_column) |dragging| moveColumn(ui, dragging, drop.target, drop.before);
    }
}

fn pushHeaderWidth(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, text: []const u8, sw: f32) ?ColumnDrop {
    const right = x.* + sw;
    const mouse = rl.getMousePosition();
    const header = rect(x.*, y, sw, h);
    const grip = rect(right - scale(ui, 5), y, scale(ui, 10), h);
    const hovered = !ui.pointer_blocked and rl.checkCollisionPointRec(mouse, header);
    const over_grip = hovered and rl.checkCollisionPointRec(mouse, grip);
    var drop: ?ColumnDrop = null;

    if (hovered and rl.isMouseButtonPressed(.left) and ui.resizing_column == null and ui.dragging_column == null) {
        if (over_grip) {
            ui.resizing_column = column;
            ui.resize_start_x = mouse.x;
            ui.resize_start_width = sw / scale(ui, 1);
        } else {
            ui.dragging_column = column;
            ui.drag_start_x = mouse.x;
            ui.drag_moved = false;
        }
    }

    if (ui.resizing_column == column) {
        requestCursor(ui, .resize_ew);
        if (rl.isMouseButtonDown(.left)) {
            ui.column_widths[column] = @max(minColumnWidth(ui, column), ui.resize_start_width + mouse.x - ui.resize_start_x);
        }
    } else if (ui.dragging_column) |dragging| {
        requestCursor(ui, .resize_all);
        if (rl.isMouseButtonDown(.left) and @abs(mouse.x - ui.drag_start_x) >= scale(ui, 4)) ui.drag_moved = true;
        if (dragging != column and ui.drag_moved and rl.isMouseButtonDown(.left) and hovered and !over_grip) {
            drop = .{ .target = column, .before = mouse.x < x.* + sw * 0.5 };
        }
    } else if (hovered) {
        requestCursor(ui, if (over_grip) .resize_ew else .pointing_hand);
    }

    const hover_t = anim(ui, widgetId(0x4ea1 + column, header), if (hovered and ui.dragging_column == null and ui.resizing_column == null) 1 else 0, 18);
    if (hover_t > 0.01) rl.drawRectangleRec(header, colors.elevated.alpha(0.55 * hover_t));
    if (ui.dragging_column == column) {
        rl.drawRectangleRec(header, colors.accent.alpha(0.16));
        rl.drawRectangleLinesEx(rect(header.x + 1, header.y + 2, header.width - 2, header.height - 4), 1, colors.accent.alpha(0.7));
    }

    const grip_t = anim(ui, widgetId(0x4ea2 + column, grip), if (over_grip) 1 else 0, 22);
    const grip_color = rl.colorLerp(colors.border, colors.accent, grip_t);
    rl.drawRectangleRec(rect(right - 1, y + scale(ui, 5), 1, h - scale(ui, 10)), grip_color);
    if (grip_t > 0.02) rl.drawRectangleRec(rect(right - scale(ui, 1) - scale(ui, 1), y + scale(ui, 5), scale(ui, 2), h - scale(ui, 10)), colors.accent.alpha(grip_t));

    const label_color = rl.colorLerp(colors.muted, colors.text, @max(hover_t, grip_t));
    drawTextClipped(ui, text, rect(x.* + scale(ui, 10), y + scale(ui, 6), sw - scale(ui, 18), h - scale(ui, 10)), label_color);
    x.* += sw;
    return drop;
}

fn drawRow(ui: *UiState, row: worker.Row, x: f32, y: f32, h: f32, visible_index: usize, row_index: usize, options: hash.HashOptions, viewport_w: f32) void {
    var appear: f32 = 1;
    var pulse: f32 = 0;
    if (row_index < ui.row_fx.items.len) {
        appear = easeOutCubic(ui.row_fx.items[row_index].appear);
        pulse = ui.row_fx.items[row_index].pulse;
    }
    const slide = (1 - appear) * scale(ui, 9);
    const draw_y = y + slide;
    const row_rect = rect(ui.table_body.x, draw_y, ui.table_body.width, h);
    const hovered = !ui.pointer_blocked and rl.checkCollisionPointRec(rl.getMousePosition(), row_rect) and !ui.dragging_vscroll and !ui.dragging_hscroll;
    const hover_t = anim(ui, 0x70b0_0000 + @as(u64, row_index), if (hovered) 1 else 0, 20);

    var bg = if (visible_index % 2 == 0) colors.panel else colors.row_alt;
    bg = rl.colorLerp(bg, colors.row_hover, hover_t);
    rl.drawRectangleRec(row_rect, bg);
    if (hover_t > 0.02) rl.drawRectangleRec(rect(row_rect.x, draw_y, scale(ui, 2), h), colors.accent.alpha(0.75 * hover_t));
    if (pulse > 0.01) rl.drawRectangleRec(row_rect, colors.accent.alpha(0.13 * pulse));
    if (appear < 0.99) rl.drawRectangleRec(row_rect, Color.init(255, 255, 255, @intFromFloat(26.0 * (1 - appear))));
    rl.drawRectangleRec(rect(row_rect.x, draw_y + h - 1, row_rect.width, 1), colors.border.alpha(0.35));

    var col_x = x;
    for (ui.column_order) |column| {
        if (!isColumnVisible(options, column)) continue;
        switch (column) {
            0 => pushCellColored(ui, &col_x, draw_y, h, column, row_index, row.file.name, colors.text, false),
            1 => pushCellColored(ui, &col_x, draw_y, h, column, row_index, sizeDisplay(row.file.size_label), colors.muted, false),
            10 => pushCellColored(ui, &col_x, draw_y, h, column, row_index, row.status, statusColor(row.status), true),
            11 => pushCellWidthColored(ui, &col_x, draw_y, h, column, row_index, row.file.path, columnWidth(ui, options, column, viewport_w), colors.path, false),
            else => {
                const algorithm: hash.Algorithm = @fromBackingInt(@intCast(column - 2));
                pushHashCell(ui, &col_x, draw_y, h, column, row_index, row.result.get(algorithm));
            },
        }
    }
}

fn sizeDisplay(label: []const u8) []const u8 {
    if (std.mem.indexOf(u8, label, " (")) |cut| return label[0..cut];
    return label;
}

fn pushCellColored(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, row: usize, text: []const u8, color: Color, pill: bool) void {
    pushCellWidthColored(ui, x, y, h, column, row, text, scale(ui, ui.column_widths[column]), color, pill);
}

fn pushCellWidthColored(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, row: usize, text: []const u8, sw: f32, color: Color, pill: bool) void {
    const cell = rect(x.*, y, sw, h);
    const selected = ui.selected_row == row and ui.selected_column == column;
    if (selected) {
        rl.drawRectangleRec(cell, colors.selected.alpha(0.42));
        rl.drawRectangleLinesEx(rect(cell.x, cell.y + 1, cell.width, cell.height - 2), 1, colors.accent);
        rl.drawRectangleLinesEx(rect(cell.x + 1, cell.y + 2, cell.width - 2, cell.height - 4), 1, colors.accent.alpha(0.28));
    }
    const mouse = rl.getMousePosition();
    if (!ui.pointer_blocked and rl.checkCollisionPointRec(mouse, cell) and rl.isMouseButtonReleased(.left) and ui.resizing_column == null) {
        ui.selected_row = row;
        ui.selected_column = column;
        const now = rl.getTime();
        const double_click = ui.last_cell_click_row == row and ui.last_cell_click_column == column and now - ui.last_cell_click_time <= 0.42;
        ui.last_cell_click_time = now;
        ui.last_cell_click_row = row;
        ui.last_cell_click_column = column;
        if (double_click) {
            const ztext = ui.allocator.dupeSentinel(u8, text, 0) catch null;
            if (ztext) |z| {
                defer ui.allocator.free(z);
                rl.setClipboardText(z);
                showToast(ui, "已复制到剪贴板");
            }
            ui.last_cell_click_time = -1;
        }
    }
    rl.drawRectangleRec(rect(x.* + sw - 1, y + scale(ui, 6), 1, h - scale(ui, 12)), colors.border.alpha(0.45));
    if (pill and text.len > 0) {
        const text_w = measureText(ui, text, sw - scale(ui, 20));
        const pill_h = scale(ui, 20);
        const pill_r = rect(x.* + scale(ui, 8), y + (h - pill_h) * 0.5, text_w + scale(ui, 26), pill_h);
        rrect(pill_r, pill_h * 0.5, color.alpha(0.14));
        drawDot(vec(pill_r.x + scale(ui, 11), pill_r.y + pill_h * 0.5), scale(ui, 3), color);
        drawTextClipped(ui, text, rect(pill_r.x + scale(ui, 18), pill_r.y, pill_r.width - scale(ui, 22), pill_h), color);
    } else {
        drawTextClipped(ui, text, rect(x.* + scale(ui, 10), y + scale(ui, 5), sw - scale(ui, 18), h - scale(ui, 9)), color);
    }
    x.* += sw;
}

fn pushHashCell(ui: *UiState, x: *f32, y: f32, h: f32, column: usize, row: usize, text: []const u8) void {
    if (!ui.app.uppercase) return pushCellColored(ui, x, y, h, column, row, text, colors.hash_value, false);
    var buf: [128]u8 = undefined;
    pushCellColored(ui, x, y, h, column, row, uppercaseInto(&buf, text), colors.hash_value, false);
}

fn statusColor(status: []const u8) Color {
    if (std.mem.indexOf(u8, status, "错误") != null or std.mem.indexOf(u8, status, "失败") != null) return colors.danger;
    if (std.mem.eql(u8, status, "完成")) return colors.success;
    if (std.mem.eql(u8, status, "排队中") or std.mem.eql(u8, status, "等待中")) return colors.warning;
    return colors.accent;
}

fn drawHorizontalScroll(ui: *UiState, area: Rect, content_w: f32, view_w: f32) void {
    const max_scroll = @max(0, content_w - view_w);
    if (max_scroll <= 0) {
        ui.dragging_hscroll = false;
        return;
    }
    const handle_w = @max(scale(ui, 56), area.width * (view_w / content_w));
    const range = area.width - handle_w;
    var handle_x = area.x + range * std.math.clamp(ui.table_scroll_x / max_scroll, 0, 1);
    var handle = rect(handle_x, area.y + scale(ui, 2), handle_w, area.height - scale(ui, 4));
    const mouse = rl.getMousePosition();
    const hover = rl.checkCollisionPointRec(mouse, handle);
    if (!ui.pointer_blocked and rl.isMouseButtonPressed(.left) and rl.checkCollisionPointRec(mouse, area)) {
        ui.dragging_hscroll = true;
        if (hover) {
            ui.hscroll_grab_offset = mouse.x - handle_x;
        } else {
            handle_x = std.math.clamp(mouse.x - handle_w * 0.5, area.x, area.x + range);
            ui.hscroll_grab_offset = handle_w * 0.5;
            ui.scroll_target_x = ((handle_x - area.x) / range) * max_scroll;
        }
    }
    if (!rl.isMouseButtonDown(.left)) ui.dragging_hscroll = false;
    if (ui.dragging_hscroll) {
        handle_x = std.math.clamp(mouse.x - ui.hscroll_grab_offset, area.x, area.x + range);
        ui.scroll_target_x = ((handle_x - area.x) / range) * max_scroll;
        ui.table_scroll_x = ui.scroll_target_x;
    }
    handle.x = handle_x;
    rrect(rect(area.x, area.y + 3, area.width, @max(2, area.height - 6)), @max(1, (area.height - 6) * 0.5), colors.scrollbar_track);
    const hover_t = anim(ui, widgetId(0x5c01, area), if (hover or ui.dragging_hscroll) 1 else 0, 16);
    const thumb = rl.colorLerp(colors.scrollbar_thumb, colors.accent_hover, hover_t);
    rrect(handle, handle.height * 0.5, if (ui.dragging_hscroll) colors.accent else thumb);
}

fn drawVerticalScroll(ui: *UiState, area: Rect, content_h: f32) void {
    const max_scroll = @max(0, content_h - area.height);
    if (max_scroll <= 0) {
        ui.dragging_vscroll = false;
        return;
    }
    const handle_h = @max(scale(ui, 56), area.height * (area.height / content_h));
    const range = area.height - handle_h;
    var handle_y = area.y + range * std.math.clamp(ui.table_scroll_y / max_scroll, 0, 1);
    var handle = rect(area.x + scale(ui, 2), handle_y, area.width - scale(ui, 4), handle_h);
    const mouse = rl.getMousePosition();
    const hover = rl.checkCollisionPointRec(mouse, handle);
    if (!ui.pointer_blocked and rl.isMouseButtonPressed(.left) and rl.checkCollisionPointRec(mouse, area)) {
        ui.dragging_vscroll = true;
        if (hover) {
            ui.vscroll_grab_offset = mouse.y - handle_y;
        } else {
            handle_y = std.math.clamp(mouse.y - handle_h * 0.5, area.y, area.y + range);
            ui.vscroll_grab_offset = handle_h * 0.5;
            ui.scroll_target_y = ((handle_y - area.y) / range) * max_scroll;
        }
    }
    if (!rl.isMouseButtonDown(.left)) ui.dragging_vscroll = false;
    if (ui.dragging_vscroll) {
        handle_y = std.math.clamp(mouse.y - ui.vscroll_grab_offset, area.y, area.y + range);
        ui.scroll_target_y = ((handle_y - area.y) / range) * max_scroll;
        ui.table_scroll_y = ui.scroll_target_y;
    }
    handle.y = handle_y;
    rrect(rect(area.x + 3, area.y, @max(2, area.width - 6), area.height), @max(1, (area.width - 6) * 0.5), colors.scrollbar_track);
    const hover_t = anim(ui, widgetId(0x5c02, area), if (hover or ui.dragging_vscroll) 1 else 0, 16);
    const thumb = rl.colorLerp(colors.scrollbar_thumb, colors.accent_hover, hover_t);
    rrect(handle, handle.width * 0.5, if (ui.dragging_vscroll) colors.accent else thumb);
}

fn isColumnVisible(options: hash.HashOptions, column: usize) bool {
    if (column <= 1 or column >= 10) return true;
    const algorithm: hash.Algorithm = @fromBackingInt(@intCast(column - 2));
    return options.enabled(algorithm);
}

fn columnLabel(column: usize) []const u8 {
    return switch (column) {
        0 => "文件",
        1 => "大小",
        10 => "状态",
        11 => "完整路径",
        else => algorithmLabelZ(@fromBackingInt(@intCast(column - 2))),
    };
}

fn columnWidth(ui: *const UiState, options: hash.HashOptions, column: usize, viewport_w: f32) f32 {
    if (column == 11) return pathColumnWidth(ui, options, viewport_w);
    return scale(ui, ui.column_widths[column]);
}

fn minColumnWidth(ui: *const UiState, column: usize) f32 {
    _ = column;
    return scale(ui, 54);
}

fn moveColumn(ui: *UiState, from_column: usize, target_column: usize, before: bool) void {
    if (from_column == target_column) return;
    const from_index = std.mem.indexOfScalar(usize, &ui.column_order, from_column) orelse return;

    var remaining: [column_count]usize = undefined;
    var remaining_count: usize = 0;
    for (ui.column_order) |column| {
        if (column == from_column) continue;
        remaining[remaining_count] = column;
        remaining_count += 1;
    }
    _ = from_index;

    const target_index = std.mem.indexOfScalar(usize, remaining[0..remaining_count], target_column) orelse return;
    const insert_index: usize = target_index + if (before) @as(usize, 0) else @as(usize, 1);
    var next: [column_count]usize = undefined;
    for (0..insert_index) |index| next[index] = remaining[index];
    next[insert_index] = from_column;
    for (insert_index..remaining_count) |index| next[index + 1] = remaining[index];
    ui.column_order = next;
}

fn totalTableWidth(ui: *UiState, options: hash.HashOptions, viewport_w: f32) f32 {
    const total = fixedTableWidth(ui, options) + pathColumnWidth(ui, options, viewport_w);
    return total;
}

fn fixedTableWidth(ui: *const UiState, options: hash.HashOptions) f32 {
    var total = ui.column_widths[0] + ui.column_widths[1] + ui.column_widths[10];
    for (hash.all_algorithms) |algorithm| {
        if (options.enabled(algorithm)) total += ui.column_widths[2 + @backingInt(algorithm)];
    }
    return scale(ui, total);
}

fn pathColumnWidth(ui: *const UiState, options: hash.HashOptions, viewport_w: f32) f32 {
    return @max(scale(ui, ui.column_widths[11]), viewport_w - fixedTableWidth(ui, options));
}

fn toolButtonEx(ui: *UiState, r: Rect, icon: Icon, label: []const u8, kind: ButtonKind, enabled: bool, active: bool) bool {
    const base = switch (kind) {
        .primary => colors.accent,
        .danger => if (active) colors.danger else colors.button,
        .normal => colors.button,
    };
    const hover_color = switch (kind) {
        .primary => colors.accent_hover,
        .danger => if (active) colors.danger_hover else colors.button_hover,
        .normal => colors.button_hover,
    };
    const down_color = switch (kind) {
        .primary => colors.accent_down,
        .danger => if (active) colors.danger_down else colors.button_down,
        .normal => colors.button_down,
    };
    const visual = buttonBaseVisual(ui, r, base, hover_color, down_color, enabled);
    if (active and kind != .primary) {
        const body = rect(r.x, r.y + visual.lift, r.width, r.height);
        rrect(body, scale(ui, layout.button_radius), colors.accent.alpha(0.10 + 0.06 * visual.hover_t));
        rrectLines(body, scale(ui, layout.button_radius), 1, colors.accent.alpha(0.42));
    }
    const foreground = if (!enabled)
        colors.muted.alpha(0.55)
    else if (kind == .primary)
        Color.init(255, 255, 255, 255)
    else if (active)
        colors.accent_hover
    else
        colors.text;
    const icon_size = @min(scale(ui, 15), r.height - scale(ui, 10));
    const icon_y = snapToPhysicalPixel(ui, r.y + visual.lift + (r.height - icon_size) * 0.5);
    if (label.len == 0) {
        drawIcon(ui, icon, rect(r.x + (r.width - icon_size) * 0.5, icon_y, icon_size, icon_size), foreground);
        return visual.clicked;
    }
    drawIcon(ui, icon, rect(r.x + scale(ui, 11), icon_y, icon_size, icon_size), foreground);
    drawTextClipped(ui, label, rect(r.x + scale(ui, 33), r.y + visual.lift, r.width - scale(ui, 40), r.height), foreground);
    return visual.clicked;
}

fn optionChip(ui: *UiState, r: Rect, label: []const u8, t: f32) bool {
    const mouse = rl.getMousePosition();
    const hover = !ui.pointer_blocked and rl.checkCollisionPointRec(mouse, r);
    const pressed = hover and rl.isMouseButtonDown(.left);
    const hover_t = anim(ui, widgetId(0xc40c, r), if (hover) 1 else 0, 18);
    if (hover) requestCursor(ui, .pointing_hand);
    const neutral = rl.colorLerp(colors.panel, colors.elevated, hover_t);
    const bg = rl.colorLerp(neutral, Color.init(27, 52, 85, 255), t);
    const lift: f32 = if (pressed) scale(ui, 0.5) else 0;
    const body = rect(r.x, r.y + lift, r.width, r.height);
    rrect(body, scale(ui, layout.button_radius), bg);
    rrectLines(body, scale(ui, layout.button_radius), 1, rl.colorLerp(colors.border, colors.accent.alpha(0.85), @max(t, hover_t * 0.55)));

    const box_size = scale(ui, 16);
    const box = rect(body.x + scale(ui, 8), body.y + (body.height - box_size) * 0.5, box_size, box_size);
    rrect(box, scale(ui, 4), rl.colorLerp(colors.input, colors.accent, t));
    rrectLines(box, scale(ui, 4), 1, rl.colorLerp(colors.border_strong, colors.accent_hover, t));
    if (t > 0.02) {
        const inset = box_size * (0.16 + 0.10 * (1 - t));
        drawIcon(ui, .check, rect(box.x + inset, box.y + inset, box_size - inset * 2, box_size - inset * 2), Color.init(255, 255, 255, @intFromFloat(255 * std.math.clamp(t, 0, 1))));
    }
    const label_color = rl.colorLerp(colors.muted, colors.text, @max(t, hover_t * 0.4));
    drawTextClipped(ui, label, rect(box.x + box_size + scale(ui, 8), body.y, body.width - box_size - scale(ui, 24), body.height), label_color);
    return hover and rl.isMouseButtonReleased(.left);
}

fn buttonBaseVisual(ui: *UiState, r: Rect, base: Color, hover_color: Color, down_color: Color, enabled: bool) ButtonVisual {
    const mouse = rl.getMousePosition();
    const hover = enabled and !ui.pointer_blocked and rl.checkCollisionPointRec(mouse, r);
    const down = hover and rl.isMouseButtonDown(.left);
    const hover_t = anim(ui, widgetId(0x8b01, r), if (hover) 1 else 0, 18);
    if (hover and enabled) requestCursor(ui, .pointing_hand);
    const lift: f32 = if (down) scale(ui, 1) else -scale(ui, 1) * hover_t * 0.6;
    const body = rect(r.x, r.y + lift, r.width, r.height);
    const radius = scale(ui, layout.button_radius);
    drawShadow(body, radius, @intFromFloat(42.0 * hover_t));
    rrect(body, radius, if (!enabled) colors.button_disabled else if (down) down_color else rl.colorLerp(base, hover_color, hover_t));
    rrectLines(body, radius, 1, if (!enabled) colors.border else rl.colorLerp(colors.border, colors.accent.alpha(0.8), hover_t));
    return .{ .clicked = hover and rl.isMouseButtonReleased(.left), .hovered = hover, .pressed = down, .hover_t = hover_t, .lift = lift };
}

fn filterButton(ui: *UiState, r: Rect) bool {
    const previous_blocked = ui.pointer_blocked;
    ui.pointer_blocked = false;
    const visual = buttonBaseVisual(ui, r, colors.button, colors.button_hover, colors.button_down, true);
    ui.pointer_blocked = previous_blocked;
    const chevron = anim(ui, widgetId(0x7f11, r), if (ui.filter_open) 1 else 0, 20);
    const label = currentFilterLabel(ui);
    const label_color = if (ui.filter_column == @backingInt(FilterColumn.all)) colors.muted else colors.accent_hover;
    drawTextClipped(ui, label, rect(r.x + scale(ui, 12), r.y + visual.lift, r.width - scale(ui, 36), r.height), label_color);
    const icon_size = scale(ui, 14);
    const icon_rect = rect(r.x + r.width - scale(ui, 24), r.y + visual.lift + (r.height - icon_size) * 0.5, icon_size, icon_size);
    const rotated = rect(icon_rect.x, icon_rect.y + chevron * scale(ui, 1.5), icon_rect.width, icon_rect.height);
    drawIcon(ui, .chevron_down, rotated, rl.colorLerp(colors.muted, colors.text, chevron));
    return visual.clicked;
}

fn drawFilterPopup(ui: *UiState) void {
    ui.filter_anim = approach(ui.filter_anim, if (ui.filter_open) 1 else 0, 22, ui.dt);
    if (ui.filter_anim <= 0.01) return;
    const t = easeOutCubic(ui.filter_anim);
    const row_h = scale(ui, 27);
    const w = @max(ui.filter_button_rect.width, scale(ui, 172));
    const popup_h = row_h * @as(f32, @floatFromInt(filter_labels.len)) + scale(ui, 10);
    const screen_w: f32 = @floatFromInt(rl.getScreenWidth());
    const screen_h: f32 = @floatFromInt(rl.getScreenHeight());
    const x = std.math.clamp(ui.filter_button_rect.x, scale(ui, 6), @max(scale(ui, 6), screen_w - w - scale(ui, 6)));
    var y = ui.filter_button_rect.y + ui.filter_button_rect.height + scale(ui, 4);
    if (y + popup_h > screen_h - scale(ui, 6)) y = @max(scale(ui, 6), ui.filter_button_rect.y - popup_h - scale(ui, 4));
    y += (1 - t) * scale(ui, 6);
    const alpha = std.math.clamp(t, 0, 1);
    const popup = rect(x, y, w, popup_h);
    drawShadow(popup, scale(ui, 9), @intFromFloat(120 * alpha));
    rrect(popup, scale(ui, 9), colors.panel.alpha(alpha));
    rrectLines(popup, scale(ui, 9), 1, colors.border.alpha(alpha));

    const mouse = rl.getMousePosition();
    const interactive = ui.filter_open and t > 0.5;
    for (filter_labels, 0..) |label, index| {
        const row_rect = rect(x + scale(ui, 5), y + scale(ui, 5) + row_h * @as(f32, @floatFromInt(index)), w - scale(ui, 10), row_h);
        const hover = interactive and rl.checkCollisionPointRec(mouse, row_rect);
        const hover_t = anim(ui, widgetId(0x7f20 + index, row_rect), if (hover) 1 else 0, 20);
        if (hover_t > 0.02) rrect(row_rect, scale(ui, 6), colors.elevated.alpha(0.9 * hover_t * alpha));
        const active = ui.filter_column == @as(i32, @intCast(index));
        if (active) {
            rrect(row_rect, scale(ui, 6), colors.accent.alpha(0.14 * alpha));
            drawDot(vec(row_rect.x + scale(ui, 6), row_rect.y + row_rect.height * 0.5), scale(ui, 2.5), colors.accent.alpha(alpha));
        }
        drawTextClipped(ui, label, rect(row_rect.x + scale(ui, 15), row_rect.y, row_rect.width - scale(ui, 22), row_rect.height), (if (active) colors.accent_hover else colors.text).alpha(alpha));
        if (active) drawIcon(ui, .check, rect(row_rect.x + row_rect.width - scale(ui, 22), row_rect.y + (row_rect.height - scale(ui, 13)) * 0.5, scale(ui, 13), scale(ui, 13)), colors.accent.alpha(alpha));
        if (hover and rl.isMouseButtonReleased(.left)) {
            ui.filter_column = @intCast(index);
            ui.filter_open = false;
            ui.scroll_target_y = 0;
        }
    }
    if (rl.isMouseButtonReleased(.left) and !rl.checkCollisionPointRec(mouse, popup) and !rl.checkCollisionPointRec(mouse, ui.filter_button_rect)) ui.filter_open = false;
}

fn showToast(ui: *UiState, message: []const u8) void {
    ui.toast_text = message;
    ui.toast_start = ui.now;
    ui.toast_duration = 1.9;
    ui.toast_until = ui.now + ui.toast_duration;
}

fn drawToast(ui: *UiState, screen_w: f32, screen_h: f32) void {
    const remaining = ui.toast_until - ui.now;
    if (remaining <= 0 or ui.toast_text.len == 0) return;
    const elapsed = @max(0, ui.now - ui.toast_start);
    const enter = easeOutCubic(@floatCast(elapsed / 0.26));
    const leave = easeOutCubic(@floatCast(std.math.clamp(remaining / 0.34, 0, 1)));
    const alpha = @min(enter, leave);
    const toast_w = @min(screen_w - scale(ui, 24), measureText(ui, ui.toast_text, screen_w) + scale(ui, 52));
    const toast_h = scale(ui, 38);
    const toast = rect((screen_w - toast_w) * 0.5, screen_h - toast_h - scale(ui, 26) + (1 - enter) * scale(ui, 20), toast_w, toast_h);
    drawShadow(toast, toast_h * 0.5, @intFromFloat(110 * alpha));
    rrect(toast, toast_h * 0.5, colors.panel2.alpha(alpha));
    rrectLines(toast, toast_h * 0.5, 1, colors.accent.alpha(0.6 * alpha));
    const icon_size = scale(ui, 16) * (0.7 + 0.3 * enter);
    drawIcon(ui, .check, rect(toast.x + scale(ui, 13), toast.y + (toast.height - icon_size) * 0.5, icon_size, icon_size), colors.success.alpha(alpha));
    drawTextCentered(ui, ui.toast_text, rect(toast.x + scale(ui, 34), toast.y, toast.width - scale(ui, 46), toast.height), colors.text.alpha(alpha));
}

fn drawSearch(ui: *UiState, r: Rect) void {
    const mouse = rl.getMousePosition();
    const hovered = !ui.pointer_blocked and rl.checkCollisionPointRec(mouse, r);
    const text = ui.search_buf[0..ui.search_len];
    const clear = rect(r.x + r.width - scale(ui, 25), r.y + (r.height - scale(ui, 19)) * 0.5, scale(ui, 19), scale(ui, 19));
    const clear_hover = text.len > 0 and !ui.pointer_blocked and rl.checkCollisionPointRec(mouse, clear);
    if (!ui.pointer_blocked and rl.isMouseButtonPressed(.left) and !clear_hover) ui.search_active = hovered;
    if (hovered or ui.search_active) requestCursor(ui, .ibeam);

    ui.search_focus_anim = approach(ui.search_focus_anim, if (ui.search_active) 1 else 0, 15, ui.dt);
    const hover_t = anim(ui, widgetId(0x5ea2, r), if (hovered) 1 else 0, 18);
    rrect(r, scale(ui, 7), colors.input);
    if (ui.search_focus_anim > 0.02) rrectLines(rect(r.x - 2, r.y - 2, r.width + 4, r.height + 4), scale(ui, 9), 1, colors.accent.alpha(0.20 * ui.search_focus_anim));
    rrectLines(r, scale(ui, 7), 1, rl.colorLerp(colors.border, colors.accent, @max(ui.search_focus_anim, hover_t * 0.45)));

    const icon_center = vec(r.x + scale(ui, 16), r.y + r.height * 0.5);
    const icon_tint = rl.colorLerp(colors.faint, colors.accent_hover, ui.search_focus_anim);
    rl.drawRing(icon_center, scale(ui, 4.1) - scale(ui, 0.7), scale(ui, 4.1) + scale(ui, 0.7), 0, 360, 32, icon_tint);
    rl.drawLineEx(vec(icon_center.x + scale(ui, 4.5), icon_center.y + scale(ui, 4.5)), vec(icon_center.x + scale(ui, 7.4), icon_center.y + scale(ui, 7.4)), scale(ui, 1.4), icon_tint);

    const text_rect = rect(r.x + scale(ui, 27), r.y + scale(ui, 4), r.width - scale(ui, 54), r.height - scale(ui, 8));
    drawTextClipped(ui, if (text.len == 0) "搜索" else text, text_rect, if (text.len == 0) colors.faint else colors.text);

    if (text.len > 0) {
        if (clear_hover) {
            rrect(clear, clear.width * 0.5, colors.elevated);
            requestCursor(ui, .pointing_hand);
        }
        drawIcon(ui, .close, rect(clear.x + scale(ui, 4.5), clear.y + scale(ui, 4.5), clear.width - scale(ui, 9), clear.height - scale(ui, 9)), if (clear_hover) colors.text else colors.faint);
        if (clear_hover and rl.isMouseButtonReleased(.left)) {
            @memset(&ui.search_buf, 0);
            ui.search_len = 0;
        }
    }

    if (ui.search_active) {
        const phase = @mod(@as(f32, @floatCast(ui.now)), 1.08) / 1.08;
        const blink = 1.0 - std.math.clamp((phase - 0.56) / 0.10, 0, 1);
        if (blink > 0.02) {
            const text_w = measureText(ui, text, text_rect.width - scale(ui, 4));
            const caret_x = @min(r.x + scale(ui, 27) + text_w, clear.x - scale(ui, 4));
            rrect(rect(caret_x, r.y + scale(ui, 9), scale(ui, 1.6), r.height - scale(ui, 18)), scale(ui, 1), colors.accent.alpha(blink));
        }
    }
}

fn handleShortcuts(ui: *UiState) void {
    const ctrl = rl.isKeyDown(.left_control) or rl.isKeyDown(.right_control);
    if (ctrl and rl.isKeyPressed(.f)) {
        ui.search_active = true;
        ui.filter_open = false;
    }
    if (rl.isKeyPressed(.escape)) {
        if (ui.filter_open) ui.filter_open = false else if (ui.search_active) ui.search_active = false;
    }
    if (ctrl and !ui.search_active) {
        if (rl.isKeyPressed(.c)) copyRows(ui, true) catch {};
        if (rl.isKeyPressed(.s)) saveRows(ui, true) catch {};
    }
    if (!ui.search_active) {
        const page = @max(scale(ui, 120), ui.table_body.height * 0.9);
        if (rl.isKeyPressed(.page_down)) ui.scroll_target_y += page;
        if (rl.isKeyPressed(.page_up)) ui.scroll_target_y -= page;
        if (rl.isKeyPressed(.home)) ui.scroll_target_y = 0;
        if (rl.isKeyPressed(.end)) ui.scroll_target_y = std.math.inf(f32);
    }
    if (rl.isKeyPressed(.enter)) {
        worker.lockMutex(&ui.app.mutex);
        const processing = ui.app.processing;
        ui.app.mutex.unlock();
        if (!processing) ui.app.start() catch {};
    }
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

fn drawIcon(ui: *const UiState, icon: Icon, r: Rect, color: Color) void {
    const atlas = &(ui.lucide_atlas orelse return);
    atlas.draw(iconToLucide(icon), r, color);
}

fn iconToLucide(icon: Icon) lucide.Icon {
    return switch (icon) {
        .minimize => .minus,
        .maximize => .maximize,
        .restore => .restore,
        .close => .x,
        .check => .check,
        .play => .play,
        .stop => .square_stop,
        .clear => .trash_2,
        .copy, .copy_no_path => .clipboard_copy,
        .save => .save,
        .save_no_path => .file_x_2,
        .reset => .rotate_ccw,
        .chevron_down => .chevron_down,
        .settings => .settings,
    };
}

fn drawTextClipped(ui: *UiState, text: []const u8, r: Rect, color: Color) void {
    drawTextInRect(ui, text, r, color);
}

fn drawTextCentered(ui: *UiState, text: []const u8, r: Rect, color: Color) void {
    drawTextInRect(ui, text, r, color);
}

/// Draws one line of text centered by its ink band inside `r`, clipping and
/// ellipsizing when it overflows.
fn drawTextInRect(ui: *UiState, text: []const u8, r: Rect, color: Color) void {
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
    const y = r.y + (r.height - ui.font_ink_height) * 0.5 - ui.font_ink_top;
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
    const col: FilterColumn = @fromBackingInt(@intCast(std.math.clamp(ui.filter_column, 0, @backingInt(FilterColumn.path))));
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
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    const last = haystack.len - needle.len;
    var start: usize = 0;
    while (start <= last) : (start += 1) {
        var matched = true;
        for (needle, 0..) |nc, i| {
            if (std.ascii.toLower(haystack[start + i]) != std.ascii.toLower(nc)) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
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
    const z = try ui.allocator.dupeSentinel(u8, out.items, 0);
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
    const default_name = std.unicode.utf8ToUtf16LeStringLiteral("哈希校验结果.csv");
    @memcpy(file_buf[0..default_name.len], default_name);

    const filter = std.unicode.utf8ToUtf16LeStringLiteral("CSV Files (*.csv)\x00*.csv\x00All Files (*.*)\x00*.*\x00");
    const title = std.unicode.utf8ToUtf16LeStringLiteral("保存结果");
    const def_ext = std.unicode.utf8ToUtf16LeStringLiteral("csv");
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
    try appendCsvField(&out, ui.allocator, "文件");
    try appendCsvFieldSeparator(&out, ui.allocator, "大小");
    worker.lockMutex(&ui.app.mutex);
    defer ui.app.mutex.unlock();
    for (hash.all_algorithms) |algorithm| {
        if (ui.app.options.enabled(algorithm)) try appendCsvFieldSeparator(&out, ui.allocator, algorithm.label());
    }
    if (include_path) try appendCsvFieldSeparator(&out, ui.allocator, "完整路径");
    try out.appendSlice(ui.allocator, "\r\n");

    for (ui.app.rows.items) |row| {
        if (!rowMatches(ui, row)) continue;
        try appendCsvField(&out, ui.allocator, row.file.name);
        try appendCsvFieldSeparator(&out, ui.allocator, row.file.size_label);
        for (hash.all_algorithms) |algorithm| {
            if (!ui.app.options.enabled(algorithm)) continue;
            const value = row.result.get(algorithm);
            if (ui.app.uppercase) {
                var buf: [128]u8 = undefined;
                try appendCsvFieldSeparator(&out, ui.allocator, uppercaseInto(&buf, value));
            } else {
                try appendCsvFieldSeparator(&out, ui.allocator, value);
            }
        }
        if (include_path) try appendCsvFieldSeparator(&out, ui.allocator, row.file.path);
        try out.appendSlice(ui.allocator, "\r\n");
    }
    return out;
}

fn appendCsvFieldSeparator(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try out.append(allocator, ',');
    try appendCsvField(out, allocator, value);
}

fn appendCsvField(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    const needs_quotes = std.mem.indexOfAny(u8, value, ",\"\r\n") != null;
    if (!needs_quotes) {
        try out.appendSlice(allocator, value);
        return;
    }

    try out.append(allocator, '"');
    for (value) |character| {
        if (character == '"') try out.append(allocator, '"');
        try out.append(allocator, character);
    }
    try out.append(allocator, '"');
}

fn uppercaseInto(buf: []u8, value: []const u8) []const u8 {
    const len = @min(buf.len, value.len);
    for (value[0..len], 0..) |ch, i| buf[i] = std.ascii.toUpper(ch);
    return buf[0..len];
}

fn algorithmLabelZ(algorithm: hash.Algorithm) [:0]const u8 {
    return algorithm_labels_z[@backingInt(algorithm)];
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
