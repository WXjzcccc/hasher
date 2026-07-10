const rl = @import("raylib");

const glyph_padding = 4;
const skyline_pack_method = 1;

/// Loads a TTF font using raylib's Skyline atlas packer. The high-level
/// LoadFontFromMemory path uses a fixed row height and can overlap unusually
/// tall glyphs found in CJK fonts.
pub fn load(file_data: []const u8, font_size: i32, codepoints: []const i32) !rl.Font {
    const glyphs = try rl.loadFontData(file_data, font_size, codepoints, .default);
    errdefer rl.unloadFontData(glyphs);

    const atlas_result = try rl.genImageFontAtlas(glyphs, font_size, glyph_padding, skyline_pack_method);
    const atlas = atlas_result[0];
    const recs = atlas_result[1];
    defer rl.unloadImage(atlas);
    errdefer rl.memFree(@ptrCast(recs.ptr));

    const texture = try rl.loadTextureFromImage(atlas);
    return .{
        .baseSize = font_size,
        .glyphCount = @intCast(glyphs.len),
        .glyphPadding = glyph_padding,
        .texture = texture,
        .recs = @ptrCast(recs.ptr),
        .glyphs = @ptrCast(glyphs.ptr),
    };
}
