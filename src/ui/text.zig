//! Texto com contorno escuro de 1 pixel (guia visual: HUD).
const rl = @import("raylib");
const palette = @import("palette.zig");

pub fn outlined(s: [:0]const u8, x: i32, y: i32, size: i32, color: rl.Color) void {
    const offsets = [_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 }, .{ -1, -1 }, .{ 1, 1 }, .{ -1, 1 }, .{ 1, -1 } };
    for (offsets) |o| rl.drawText(s, x + o[0], y + o[1], size, palette.ink);
    rl.drawText(s, x, y, size, color);
}
