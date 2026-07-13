const std = @import("std");
const ui = @import("raylib_ui.zig");
const windows_dpi = @import("windows_dpi.zig");
const context_menu = @import("context_menu.zig");
const single_instance = @import("single_instance.zig");
const com_server = @import("com_server.zig");

pub fn main(init: std.process.Init) !void {
    windows_dpi.enablePerMonitorV2();
    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer iterator.deinit();
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(init.gpa);
    while (iterator.next()) |argument| try args.append(init.gpa, argument);
    const request = context_menu.parseContextHashArgs(args.items);

    var context_queue = single_instance.RequestQueue.init(init.gpa);
    defer context_queue.deinit();
    var server = com_server.Server.init(&context_queue);
    try server.start();
    defer server.deinit();

    var instance = try single_instance.acquireOrForward(init.gpa, request);
    defer instance.deinit();
    if (instance.forwarded) return;
    try ui.run(init.gpa, init.io, request, &context_queue);
}
