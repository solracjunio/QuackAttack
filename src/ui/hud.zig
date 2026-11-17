//! HUD: coluna no canto superior esquerdo, ícone + número (guia visual).
//! Lê o estado direto do mundo, sem variáveis observáveis (o plano quer
//! testar se elas fazem falta). Coordenadas da cena (resolução baixa).
const std = @import("std");
const rl = @import("raylib");
const World = @import("game").world.World;
const palette = @import("palette.zig");
const text = @import("text.zig");

const margin = 6;
const font_size = 10; // fonte padrão em pixel, sem escala dentro da cena
const icon_size = 8;
const gap = 4;

pub fn draw(w: World) void {
    heart(margin, margin);
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrintSentinel(&buf, "{d}/{d}", .{ w.queue_health.current, w.queue_health.max }, 0) catch return;
    text.outlined(s, margin + icon_size + gap, margin, font_size, palette.text);
}

/// Coração de `icon_size` com o canto superior esquerdo em (x, y).
fn heart(x: f32, y: f32) void {
    const lobe = icon_size / 4;
    rl.drawCircleV(.{ .x = x + lobe, .y = y + lobe + 1 }, lobe + 0.5, palette.life);
    rl.drawCircleV(.{ .x = x + icon_size - lobe, .y = y + lobe + 1 }, lobe + 0.5, palette.life);
    rl.drawTriangle(
        .{ .x = x, .y = y + lobe + 1 },
        .{ .x = x + icon_size / 2, .y = y + icon_size },
        .{ .x = x + icon_size, .y = y + lobe + 1 },
        palette.life,
    );
}
