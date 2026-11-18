//! HUD: coluna no canto superior esquerdo, ícone + número (guia visual), mais
//! os avisos no centro: pausa entre ondas e fim de jogo. Lê o estado direto do
//! mundo, sem variáveis observáveis. Coordenadas da cena (resolução baixa).
const std = @import("std");
const rl = @import("raylib");
const World = @import("game").world.World;
const palette = @import("palette.zig");
const text = @import("text.zig");
const scene = @import("scene.zig");

const margin = 6;
const font_size = 10; // fonte padrão em pixel, sem escala dentro da cena
const title_size = 20;
const icon_size = 8;
const gap = 4;
const row_height = 12;
/// Linhas da coluna do HUD (vida e onda).
const rows = 2;
/// Onde a coluna do HUD termina, em pixels da cena: quem desenha embaixo dela
/// (o overlay de debug) começa daqui.
pub const bottom = margin + rows * row_height;

pub fn draw(w: World) void {
    const width: i32 = @intFromFloat(w.config.world.width / scene.pixel_scale);
    const height: i32 = @intFromFloat(w.config.world.height / scene.pixel_scale);
    const dead = w.queue_health.isDead();
    // Fim de jogo: escurece a cena antes da coluna, para o HUD continuar legível.
    if (dead) rl.drawRectangle(0, 0, width, height, palette.dim);

    var buf: [64]u8 = undefined;
    heart(margin, margin);
    row(0, std.fmt.bufPrintSentinel(&buf, "{d}/{d}", .{ w.queue_health.current, w.queue_health.max }, 0) catch return);
    flag(margin, margin + row_height);
    row(1, std.fmt.bufPrintSentinel(&buf, "{d}", .{w.wave + 1}, 0) catch return);

    if (dead) {
        gameOver(w, width, height);
    } else if (w.wave_break > 0) {
        const s = std.fmt.bufPrintSentinel(&buf, "Onda {d} em {d:.1}s", .{ w.wave + 1, w.wave_break }, 0) catch return;
        centered(s, @divTrunc(height, 3), font_size, palette.banner, width);
    }
}

fn row(index: i32, s: [:0]const u8) void {
    text.outlined(s, margin + icon_size + gap, margin + index * row_height, font_size, palette.text);
}

fn gameOver(w: World, width: i32, height: i32) void {
    var buf: [64]u8 = undefined;
    const mid = @divTrunc(height, 2);
    centered("FIM DE JOGO", mid - title_size, title_size, palette.life, width);
    const reached = std.fmt.bufPrintSentinel(&buf, "Chegou na onda {d}", .{w.wave + 1}, 0) catch return;
    centered(reached, mid + gap, font_size, palette.text, width);
    centered("R para recomeçar", mid + gap + row_height, font_size, palette.text, width);
}

fn centered(s: [:0]const u8, y: i32, size: i32, color: rl.Color, width: i32) void {
    const x = @divTrunc(width - rl.measureText(s, size), 2);
    text.outlined(s, x, y, size, color);
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

/// Bandeirinha da onda: mastro e flâmula, com o canto superior esquerdo em (x, y).
fn flag(x: f32, y: f32) void {
    rl.drawRectangleV(.{ .x = x + 1, .y = y }, .{ .x = 1, .y = icon_size }, palette.banner);
    rl.drawTriangle(
        .{ .x = x + 2, .y = y },
        .{ .x = x + 2, .y = y + icon_size / 2 + 1 },
        .{ .x = x + icon_size, .y = y + icon_size / 4 },
        palette.banner,
    );
}
