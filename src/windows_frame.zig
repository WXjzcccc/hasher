const builtin = @import("builtin");

const WndProc = *const fn (?*anyopaque, u32, usize, isize) callconv(.winapi) isize;
const Point = extern struct { x: i32, y: i32 };
const WinRect = extern struct { left: i32, top: i32, right: i32, bottom: i32 };
const WindowPos = extern struct {
    hwnd: ?*anyopaque,
    insert_after: ?*anyopaque,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    flags: u32,
};
const NcCalcSizeParams = extern struct {
    rects: [3]WinRect,
    window_pos: *WindowPos,
};

const CopyData = extern struct {
    dw_data: usize,
    cb_data: u32,
    lp_data: ?*const anyopaque,
};

pub const CopyDataHandler = *const fn (?*anyopaque, []const u8) void;

extern "dwmapi" fn DwmSetWindowAttribute(hwnd: ?*anyopaque, attribute: u32, value: ?*const anyopaque, value_size: u32) callconv(.winapi) i32;
extern "gdi32" fn CreateRoundRectRgn(left: i32, top: i32, right: i32, bottom: i32, width: i32, height: i32) callconv(.winapi) ?*anyopaque;
extern "user32" fn SetWindowRgn(hwnd: ?*anyopaque, region: ?*anyopaque, redraw: bool) callconv(.winapi) c_int;
extern "user32" fn GetWindowLongPtrW(hwnd: ?*anyopaque, index: c_int) callconv(.winapi) isize;
extern "user32" fn SetWindowLongPtrW(hwnd: ?*anyopaque, index: c_int, value: isize) callconv(.winapi) isize;
extern "user32" fn CallWindowProcW(previous: ?WndProc, hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize;
extern "user32" fn SetWindowPos(hwnd: ?*anyopaque, insert_after: ?*anyopaque, x: c_int, y: c_int, width: c_int, height: c_int, flags: c_uint) callconv(.winapi) bool;
extern "user32" fn GetCursorPos(point: *Point) callconv(.winapi) bool;
extern "user32" fn ScreenToClient(hwnd: ?*anyopaque, point: *Point) callconv(.winapi) bool;
extern "user32" fn GetClientRect(hwnd: ?*anyopaque, rect: *WinRect) callconv(.winapi) bool;
extern "user32" fn GetWindowRect(hwnd: ?*anyopaque, rect: *WinRect) callconv(.winapi) bool;
extern "user32" fn GetDpiForWindow(hwnd: ?*anyopaque) callconv(.winapi) u32;
extern "user32" fn GetSystemMetricsForDpi(index: c_int, dpi: u32) callconv(.winapi) c_int;
extern "user32" fn IsZoomed(hwnd: ?*anyopaque) callconv(.winapi) bool;
extern "user32" fn SendMessageW(hwnd: ?*anyopaque, message: c_uint, wparam: usize, lparam: isize) callconv(.winapi) isize;
extern "user32" fn SetCapture(hwnd: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "user32" fn ReleaseCapture() callconv(.winapi) bool;

const gwl_style: c_int = -16;
const gwlp_wndproc: c_int = -4;
const ws_caption: usize = 0x00C0_0000;
const ws_thickframe: usize = 0x0004_0000;
const ws_minimizebox: usize = 0x0002_0000;
const ws_maximizebox: usize = 0x0001_0000;
const ws_sysmenu: usize = 0x0008_0000;
const swp_framechanged: c_uint = 0x0020;
const swp_nomove: c_uint = 0x0002;
const swp_nosize: c_uint = 0x0001;
const swp_nozorder: c_uint = 0x0004;
const swp_noactivate: c_uint = 0x0010;
const wm_nccalcsize: u32 = 0x0083;
const wm_nchittest: u32 = 0x0084;
pub const wm_copydata: u32 = 0x004A;
const wm_syscommand: c_uint = 0x0112;
const wm_close: c_uint = 0x0010;
const sm_cxframe: c_int = 32;
const sm_cyframe: c_int = 33;
const sm_cxpaddedborder: c_int = 92;
const sc_minimize: usize = 0xF020;
const sc_maximize: usize = 0xF030;
const sc_restore: usize = 0xF120;
const ht_client: isize = 1;
const ht_caption: isize = 2;
pub const copy_data_id: usize = 0x4841_5348;

var installed_hwnd: ?*anyopaque = null;
var previous_wnd_proc: ?WndProc = null;
var copy_data_context: ?*anyopaque = null;
var copy_data_handler: ?CopyDataHandler = null;

pub fn setCopyDataHandler(context: ?*anyopaque, handler: ?CopyDataHandler) void {
    copy_data_context = context;
    copy_data_handler = handler;
}

pub const ResizeSession = struct {
    hit_test: c_int,
    start_cursor: Point,
    start_rect: WinRect,
};

/// Adds the standard caption/minimize/maximize styles needed by DWM animations,
/// while a native hit-test procedure keeps the app's custom-drawn titlebar.
pub fn installNativeFrame(hwnd: ?*anyopaque) void {
    if (builtin.os.tag != .windows or hwnd == null or installed_hwnd == hwnd) return;

    const old_proc = SetWindowLongPtrW(hwnd, gwlp_wndproc, @bitCast(@intFromPtr(&windowProc)));
    if (old_proc == 0) return;
    previous_wnd_proc = @ptrFromInt(@as(usize, @bitCast(old_proc)));
    installed_hwnd = hwnd;

    const current_style: usize = @bitCast(GetWindowLongPtrW(hwnd, gwl_style));
    const style = current_style | ws_caption | ws_thickframe | ws_minimizebox | ws_maximizebox | ws_sysmenu;
    _ = SetWindowLongPtrW(hwnd, gwl_style, @bitCast(style));
    _ = SetWindowPos(hwnd, null, 0, 0, 0, 0, swp_framechanged | swp_nomove | swp_nosize | swp_nozorder | swp_noactivate);
}

/// Requests Windows 11 rounded corners and applies a matching region because
/// the app intentionally draws its own frame.
pub fn updateRoundedFrame(hwnd: ?*anyopaque, width: i32, height: i32, maximized: bool) void {
    if (builtin.os.tag != .windows or width <= 0 or height <= 0) return;

    const preference: i32 = 2;
    _ = DwmSetWindowAttribute(hwnd, 33, @ptrCast(&preference), @sizeOf(@TypeOf(preference)));
    if (maximized) {
        _ = SetWindowRgn(hwnd, null, true);
        return;
    }

    const region = CreateRoundRectRgn(0, 0, width + 1, height + 1, 24, 24) orelse return;
    _ = SetWindowRgn(hwnd, region, true);
}

pub fn minimize(hwnd: ?*anyopaque) void {
    if (builtin.os.tag == .windows) _ = SendMessageW(hwnd, wm_syscommand, sc_minimize, 0);
}

pub fn toggleMaximize(hwnd: ?*anyopaque, maximized: bool) void {
    if (builtin.os.tag == .windows) _ = SendMessageW(hwnd, wm_syscommand, if (maximized) sc_restore else sc_maximize, 0);
}

pub fn close(hwnd: ?*anyopaque) void {
    if (builtin.os.tag == .windows) _ = SendMessageW(hwnd, wm_close, 0, 0);
}

pub fn beginResize(hwnd: ?*anyopaque, hit_test: c_int) ?ResizeSession {
    if (builtin.os.tag != .windows) return null;
    var cursor = Point{ .x = 0, .y = 0 };
    var window_rect = WinRect{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    if (!GetCursorPos(&cursor) or !GetWindowRect(hwnd, &window_rect)) return null;
    _ = SetCapture(hwnd);
    return .{ .hit_test = hit_test, .start_cursor = cursor, .start_rect = window_rect };
}

pub fn updateResize(hwnd: ?*anyopaque, session: ResizeSession, min_width: i32, min_height: i32) void {
    if (builtin.os.tag != .windows) return;
    var cursor = Point{ .x = 0, .y = 0 };
    if (!GetCursorPos(&cursor)) return;
    const dx = cursor.x - session.start_cursor.x;
    const dy = cursor.y - session.start_cursor.y;
    var next = session.start_rect;
    switch (session.hit_test) {
        10, 13, 16 => next.left += dx,
        11, 14, 17 => next.right += dx,
        else => {},
    }
    switch (session.hit_test) {
        12, 13, 14 => next.top += dy,
        15, 16, 17 => next.bottom += dy,
        else => {},
    }
    if (next.right - next.left < min_width) {
        if (session.hit_test == 10 or session.hit_test == 13 or session.hit_test == 16) next.left = next.right - min_width else next.right = next.left + min_width;
    }
    if (next.bottom - next.top < min_height) {
        if (session.hit_test == 12 or session.hit_test == 13 or session.hit_test == 14) next.top = next.bottom - min_height else next.bottom = next.top + min_height;
    }
    _ = SetWindowPos(hwnd, null, next.left, next.top, next.right - next.left, next.bottom - next.top, swp_nozorder | swp_noactivate);
}

pub fn endResize() void {
    if (builtin.os.tag == .windows) _ = ReleaseCapture();
}

fn windowProc(hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    switch (message) {
        wm_nccalcsize => if (wparam != 0) {
            if (IsZoomed(hwnd)) adjustMaximizedClientRect(hwnd, lparam);
            return 0;
        },
        wm_nchittest => return hitTest(hwnd),
        wm_copydata => if (dispatchCopyData(lparam)) return 1,
        else => {},
    }
    return CallWindowProcW(previous_wnd_proc, hwnd, message, wparam, lparam);
}

fn dispatchCopyData(lparam: isize) bool {
    if (lparam == 0) return false;
    const data: *const CopyData = @ptrFromInt(@as(usize, @bitCast(lparam)));
    if (data.dw_data != copy_data_id or data.cb_data == 0 or data.lp_data == null) return false;
    const bytes: [*]const u8 = @ptrCast(data.lp_data.?);
    if (copy_data_handler) |handler| handler(copy_data_context, bytes[0..data.cb_data]);
    return copy_data_handler != null;
}

fn adjustMaximizedClientRect(hwnd: ?*anyopaque, lparam: isize) void {
    if (lparam == 0) return;
    const params: *NcCalcSizeParams = @ptrFromInt(@as(usize, @bitCast(lparam)));
    const dpi = @max(@as(u32, 96), GetDpiForWindow(hwnd));
    const padded_border = GetSystemMetricsForDpi(sm_cxpaddedborder, dpi);
    const border_x = GetSystemMetricsForDpi(sm_cxframe, dpi) + padded_border;
    const border_y = GetSystemMetricsForDpi(sm_cyframe, dpi) + padded_border;
    params.rects[0].left += border_x;
    params.rects[0].top += border_y;
    params.rects[0].right -= border_x;
    params.rects[0].bottom -= border_y;
}

fn hitTest(hwnd: ?*anyopaque) isize {
    var point = Point{ .x = 0, .y = 0 };
    var client = WinRect{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    if (!GetCursorPos(&point) or !ScreenToClient(hwnd, &point) or !GetClientRect(hwnd, &client)) return ht_client;

    const dpi = @max(@as(u32, 96), GetDpiForWindow(hwnd));
    const title_height: i32 = @intCast((34 * dpi + 95) / 96);
    const button_band: i32 = @intCast((138 * dpi + 95) / 96);
    if (point.y >= 0 and point.y < title_height and point.x >= 0 and point.x < client.right - button_band) return ht_caption;
    return ht_client;
}
