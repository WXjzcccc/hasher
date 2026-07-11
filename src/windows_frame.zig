const builtin = @import("builtin");

const WndProc = *const fn (?*anyopaque, u32, usize, isize) callconv(.winapi) isize;
const Point = extern struct { x: i32, y: i32 };
const WinRect = extern struct { left: i32, top: i32, right: i32, bottom: i32 };

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
extern "user32" fn GetDpiForWindow(hwnd: ?*anyopaque) callconv(.winapi) u32;
extern "user32" fn IsZoomed(hwnd: ?*anyopaque) callconv(.winapi) bool;
extern "user32" fn SendMessageW(hwnd: ?*anyopaque, message: c_uint, wparam: usize, lparam: isize) callconv(.winapi) isize;

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
const wm_syscommand: c_uint = 0x0112;
const wm_close: c_uint = 0x0010;
const sc_minimize: usize = 0xF020;
const sc_maximize: usize = 0xF030;
const sc_restore: usize = 0xF120;
const ht_client: isize = 1;
const ht_caption: isize = 2;
const ht_left: isize = 10;
const ht_right: isize = 11;
const ht_top: isize = 12;
const ht_top_left: isize = 13;
const ht_top_right: isize = 14;
const ht_bottom: isize = 15;
const ht_bottom_left: isize = 16;
const ht_bottom_right: isize = 17;

var installed_hwnd: ?*anyopaque = null;
var previous_wnd_proc: ?WndProc = null;

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

fn windowProc(hwnd: ?*anyopaque, message: u32, wparam: usize, lparam: isize) callconv(.winapi) isize {
    switch (message) {
        wm_nccalcsize => if (wparam != 0) return 0,
        wm_nchittest => return hitTest(hwnd),
        else => {},
    }
    return CallWindowProcW(previous_wnd_proc, hwnd, message, wparam, lparam);
}

fn hitTest(hwnd: ?*anyopaque) isize {
    var point = Point{ .x = 0, .y = 0 };
    var client = WinRect{ .left = 0, .top = 0, .right = 0, .bottom = 0 };
    if (!GetCursorPos(&point) or !ScreenToClient(hwnd, &point) or !GetClientRect(hwnd, &client)) return ht_client;

    const dpi = @max(@as(u32, 96), GetDpiForWindow(hwnd));
    const edge: i32 = @intCast((7 * dpi + 95) / 96);
    const title_height: i32 = @intCast((34 * dpi + 95) / 96);
    const button_band: i32 = @intCast((132 * dpi + 95) / 96);
    if (!IsZoomed(hwnd)) {
        const left = point.x >= client.left and point.x < client.left + edge;
        const right = point.x < client.right and point.x >= client.right - edge;
        const top = point.y >= client.top and point.y < client.top + edge;
        const bottom = point.y < client.bottom and point.y >= client.bottom - edge;
        if (top and left) return ht_top_left;
        if (top and right) return ht_top_right;
        if (bottom and left) return ht_bottom_left;
        if (bottom and right) return ht_bottom_right;
        if (left) return ht_left;
        if (right) return ht_right;
        if (top) return ht_top;
        if (bottom) return ht_bottom;
    }
    if (point.y >= 0 and point.y < title_height and point.x >= 0 and point.x < client.right - button_band) return ht_caption;
    return ht_client;
}
