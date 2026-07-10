const std = @import("std");
const ui = @import("raylib_ui.zig");
const windows_dpi = @import("windows_dpi.zig");

pub fn main(init: std.process.Init) !void {
    windows_dpi.enablePerMonitorV2();
    try ui.run(init.gpa, init.io);
}
