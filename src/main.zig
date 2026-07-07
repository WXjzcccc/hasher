const std = @import("std");
const ui = @import("raylib_ui.zig");

pub fn main(init: std.process.Init) !void {
    try ui.run(init.gpa, init.io);
}
