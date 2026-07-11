const std = @import("std");
const ui = @import("raylib_ui.zig");
const windows_dpi = @import("windows_dpi.zig");
const context_menu = @import("context_menu.zig");

pub fn main(init: std.process.Init) !void {
    windows_dpi.enablePerMonitorV2();
    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer iterator.deinit();
    var args: [4][]const u8 = undefined;
    var count: usize = 0;
    while (iterator.next()) |argument| {
        if (count < args.len) args[count] = argument;
        count += 1;
    }
    const request = if (count == args.len) context_menu.parseContextHashArgs(&args) else null;
    try ui.run(init.gpa, init.io, request);
}
