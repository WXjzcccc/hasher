const builtin = @import("builtin");

extern "user32" fn SetProcessDpiAwarenessContext(value: ?*anyopaque) callconv(.winapi) bool;

/// The embedded application manifest establishes Per-Monitor V2 before process
/// initialization. This call is retained as a fallback for non-standard launchers
/// that do not apply the executable manifest.
pub fn enablePerMonitorV2() void {
    if (builtin.os.tag != .windows) return;

    const per_monitor_aware_v2: isize = -4;
    const context: ?*anyopaque = @ptrFromInt(@as(usize, @bitCast(per_monitor_aware_v2)));
    _ = SetProcessDpiAwarenessContext(context);
}
