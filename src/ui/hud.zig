//! HUD: vida da fila. Lê o estado direto do mundo, sem variáveis observáveis
//! (o plano quer testar se elas fazem falta).
const std = @import("std");
const rl = @import("raylib");
const World = @import("game").world.World;

const margin = 12;
const font_size = 24;
const color: rl.Color = .white;

pub fn draw(w: World) void {
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrintSentinel(&buf, "Vida {d}/{d}", .{ w.queue_health.current, w.queue_health.max }, 0) catch return;
    rl.drawText(text, margin, margin, font_size, color);
}
