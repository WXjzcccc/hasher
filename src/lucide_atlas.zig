const rl = @import("raylib");

pub const Icon = enum {
    minus,
    maximize,
    restore,
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

pub const Atlas = struct {
    texture: rl.Texture2D,

    pub fn init(png: []const u8) !Atlas {
        const image = try rl.loadImageFromMemory(".png", png);
        defer rl.unloadImage(image);
        const texture = try rl.loadTextureFromImage(image);
        rl.setTextureFilter(texture, .bilinear);
        return .{ .texture = texture };
    }

    pub fn deinit(self: *Atlas) void {
        rl.unloadTexture(self.texture);
    }

    pub fn draw(self: *const Atlas, icon: Icon, bounds: rl.Rectangle, color: rl.Color) void {
        const source_size: f32 = @as(f32, @floatFromInt(self.texture.height));
        var source_index: usize = @intFromEnum(icon);
        if (icon == .restore) source_index = @intFromEnum(Icon.maximize);
        const source = rl.Rectangle.init(source_size * @as(f32, @floatFromInt(source_index)), 0, source_size, source_size);
        rl.drawTexturePro(self.texture, source, bounds, .{ .x = 0, .y = 0 }, 0, color);
        if (icon == .restore) {
            const inset = @max(1, bounds.width * 0.14);
            const shifted = rl.Rectangle.init(bounds.x - inset, bounds.y + inset, bounds.width - inset, bounds.height - inset);
            rl.drawTexturePro(self.texture, source, shifted, .{ .x = 0, .y = 0 }, 0, color);
        }
    }
};
