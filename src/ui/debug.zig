//! Overlay de debug (F1): FPS, quantidade de entidades e os eventos do frame.
const std = @import("std");
const rl = @import("raylib");
const game = @import("game");
const World = game.world.World;
const Event = game.events.Event;

const x = 12;
const top = 48;
const line_height = 18;
const font_size = 16;
const max_event_lines = 20;
const panel_width = 360;
const palette = @import("palette.zig");
const panel = palette.panel;
const text_color = palette.text;

pub fn draw(w: World, frame_events: []const Event) void {
    var lines: usize = 0;
    // Tipo explícito: com uma constante, o `@min` devolve um inteiro estreito (u5) que estoura na conta abaixo.
    const shown: usize = @min(frame_events.len, max_event_lines);
    const height = (4 + shown) * line_height;
    rl.drawRectangle(x - 4, top - 4, panel_width, @intCast(height + 8), panel);

    var buf: [128]u8 = undefined;
    line(&lines, &buf, "FPS {d}", .{rl.getFPS()});
    line(&lines, &buf, "patinhos {d}  inimigos {d}  flechas {d}", .{ w.ducks.len, w.enemies.count, w.projectiles.count });
    line(&lines, &buf, "invulnerável {d:.2}s  próximo inimigo {d:.2}s", .{ w.invulnerable, w.spawn_timer });
    line(&lines, &buf, "eventos no frame: {d}", .{frame_events.len});
    for (frame_events[0..shown]) |e| {
        var text_buf: [96]u8 = undefined;
        line(&lines, &buf, "  {s}", .{game.events.describe(e, &text_buf)});
    }
}

fn line(lines: *usize, buf: []u8, comptime fmt: []const u8, args: anytype) void {
    const text = std.fmt.bufPrintSentinel(buf, fmt, args, 0) catch return;
    const y: i32 = @intCast(top + lines.* * line_height);
    rl.drawText(text, x, y, font_size, text_color);
    lines.* += 1;
}
