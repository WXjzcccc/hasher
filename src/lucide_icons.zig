const rl = @import("raylib");

pub const Icon = enum {
    minus,
    maximize,
    copy,
    x,
    check,
    play,
    square_stop,
    trash_2,
    clipboard_copy,
    save,
    file_x_2,
    rotate_ccw,
    chevron_down,
    settings,
};

const Point = struct { x: f32, y: f32 };
const Segment = struct { from: Point, to: Point };
const RoundedRect = struct { x: f32, y: f32, width: f32, height: f32, radius: f32 = 2 };
const Circle = struct { x: f32, y: f32, radius: f32 };
const IconData = struct {
    segments: []const Segment = &.{},
    rects: []const RoundedRect = &.{},
    circles: []const Circle = &.{},
};

pub fn draw(icon: Icon, bounds: rl.Rectangle, color: rl.Color) void {
    const data = iconData(icon);
    const scale = @min(bounds.width, bounds.height) / 24;
    const offset_x = bounds.x + (bounds.width - 24 * scale) * 0.5;
    const offset_y = bounds.y + (bounds.height - 24 * scale) * 0.5;
    const thickness = @max(1.2, 2 * scale);
    for (data.segments) |segment| {
        rl.drawLineEx(
            point(offset_x, offset_y, scale, segment.from),
            point(offset_x, offset_y, scale, segment.to),
            thickness,
            color,
        );
    }
    for (data.rects) |shape| {
        const rect = rl.Rectangle.init(offset_x + shape.x * scale, offset_y + shape.y * scale, shape.width * scale, shape.height * scale);
        rl.drawRectangleRoundedLinesEx(rect, @min(1, shape.radius * 2 / @min(shape.width, shape.height)), 8, thickness, color);
    }
    for (data.circles) |shape| rl.drawCircleLinesV(point(offset_x, offset_y, scale, .{ .x = shape.x, .y = shape.y }), shape.radius * scale, color);
}

fn point(offset_x: f32, offset_y: f32, scale: f32, value: Point) rl.Vector2 {
    return .{ .x = offset_x + value.x * scale, .y = offset_y + value.y * scale };
}

fn iconData(icon: Icon) IconData {
    return switch (icon) {
        .minus => .{ .segments = &.{ line(5, 12, 19, 12) } },
        .maximize => .{ .rects = &.{ .{ .x = 3, .y = 3, .width = 18, .height = 18 } } },
        .copy => .{
            .rects = &.{ .{ .x = 8, .y = 8, .width = 14, .height = 14 } },
            .segments = &.{ line(4, 16, 3, 15), line(3, 15, 2, 14), line(2, 14, 2, 4), line(2, 4, 3, 3), line(3, 3, 4, 2), line(4, 2, 14, 2), line(14, 2, 15, 3), line(15, 3, 16, 4) },
        },
        .x => .{ .segments = &.{ line(18, 6, 6, 18), line(6, 6, 18, 18) } },
        .check => .{ .segments = &.{ line(20, 6, 9, 17), line(9, 17, 4, 12) } },
        .play => .{ .segments = &.{ line(6, 3, 20, 12), line(20, 12, 6, 21), line(6, 21, 6, 3) } },
        .square_stop => .{ .rects = &.{ .{ .x = 3, .y = 3, .width = 18, .height = 18 }, .{ .x = 9, .y = 9, .width = 6, .height = 6, .radius = 1 } } },
        .trash_2 => .{ .segments = &.{ line(10, 11, 10, 17), line(14, 11, 14, 17), line(19, 6, 19, 20), line(19, 20, 18, 21), line(18, 21, 17, 22), line(17, 22, 7, 22), line(7, 22, 6, 21), line(6, 21, 5, 20), line(5, 20, 5, 6), line(3, 6, 21, 6), line(8, 6, 8, 4), line(8, 4, 9, 3), line(9, 3, 10, 2), line(10, 2, 14, 2), line(14, 2, 15, 3), line(15, 3, 16, 4), line(16, 4, 16, 6) } },
        .clipboard_copy => .{
            .rects = &.{ .{ .x = 8, .y = 2, .width = 8, .height = 4, .radius = 1 } },
            .segments = &.{ line(8, 4, 6, 4), line(6, 4, 4, 6), line(4, 6, 4, 20), line(4, 20, 6, 22), line(6, 22, 18, 22), line(18, 22, 20, 20), line(20, 20, 20, 18), line(16, 4, 18, 4), line(18, 4, 20, 6), line(20, 6, 20, 10), line(21, 14, 11, 14), line(15, 10, 11, 14), line(11, 14, 15, 18) },
        },
        .save => .{
            .rects = &.{ .{ .x = 2, .y = 2, .width = 20, .height = 20 } },
            .segments = &.{ line(6, 2, 6, 8), line(6, 8, 16, 8), line(16, 8, 16, 2), line(6, 22, 6, 14), line(6, 14, 18, 14), line(18, 14, 18, 22) },
        },
        .file_x_2 => .{ .segments = &.{ line(14, 2, 6, 2), line(6, 2, 4, 4), line(4, 4, 4, 20), line(4, 20, 6, 22), line(6, 22, 18, 22), line(18, 22, 20, 20), line(20, 20, 20, 8), line(14, 2, 14, 8), line(14, 8, 20, 8), line(9, 13, 15, 19), line(15, 13, 9, 19) } },
        .rotate_ccw => .{
            .segments = &.{ line(3, 12, 3, 6), line(3, 6, 9, 6), line(3, 6, 6, 9), line(3, 6, 7, 3), line(7, 3, 12, 2), line(12, 2, 17, 4), line(17, 4, 20, 8), line(20, 8, 21, 13), line(21, 13, 19, 18), line(19, 18, 15, 21), line(15, 21, 10, 22), line(10, 22, 6, 20), line(6, 20, 3, 16) },
        },
        .chevron_down => .{ .segments = &.{ line(6, 9, 12, 15), line(12, 15, 18, 9) } },
        .settings => .{
            .circles = &.{ .{ .x = 12, .y = 12, .radius = 3 } },
            .segments = &.{ line(19.4, 15, 21, 16), line(21, 16, 22, 18), line(22, 18, 20, 21), line(20, 21, 18, 21), line(18, 21, 16.5, 19), line(16.5, 19, 14, 20), line(14, 20, 13, 22), line(13, 22, 9, 22), line(9, 22, 8, 20), line(8, 20, 5.5, 19), line(5.5, 19, 4, 21), line(4, 21, 2, 21), line(2, 21, 0, 18), line(0, 18, 1, 16), line(1, 16, 4.6, 14), line(4.6, 14, 4.6, 10), line(1, 8, 0, 6), line(0, 6, 2, 3), line(2, 3, 4, 3), line(4, 3, 5.5, 5), line(5.5, 5, 8, 4), line(8, 4, 9, 2), line(9, 2, 13, 2), line(13, 2, 14, 4), line(14, 4, 16.5, 5), line(16.5, 5, 18, 3), line(18, 3, 20, 3), line(20, 3, 22, 6), line(22, 6, 21, 8), line(21, 8, 19.4, 9) },
        },
    };
}

fn line(x1: f32, y1: f32, x2: f32, y2: f32) Segment {
    return .{ .from = .{ .x = x1, .y = y1 }, .to = .{ .x = x2, .y = y2 } };
}
