//! Sistema `spawner`: segue a onda atual. Espera a pausa entre ondas e, no
//! intervalo da onda, cria um inimigo num ponto aleatório da borda (lado e
//! posição vêm do gerador com a seed), até a onda soltar todos os dela.
const std = @import("std");
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;
const waves = @import("../waves.zig");
const expectVec = @import("../testing.zig").expectVec;

const Side = enum { left, right, top, bottom };

pub fn update(w: *World, gpa: std.mem.Allocator, dt: f32) !void {
    if (w.wave_break > 0) {
        w.wave_break = @max(w.wave_break - dt, 0);
        return;
    }
    const wave = waves.at(w.config.waves, w.wave);
    // Depois que a onda soltou todos, o temporizador segue descendo sem efeito:
    // o `ondas` o reinicia quando a onda acaba.
    w.spawn_timer -= dt;
    while (w.spawn_timer <= 0 and w.wave_spawned < wave.enemies) : (w.spawn_timer += wave.interval) {
        _ = try w.enemies.add(gpa, .{ .pos = borderPoint(w), .health = .init(w.config.enemy.life) });
        w.wave_spawned += 1;
    }
}

/// Ponto aleatório encostado numa das quatro bordas, contando o raio do inimigo.
fn borderPoint(w: *World) Vec2 {
    const random = w.rng.random();
    const side = random.enumValueWithIndex(Side, u8);
    return pointOnSide(w.*, side, random.float(f32));
}

/// Ponto no lado `side`, a uma fração `t` (0 a 1) do comprimento útil dele.
fn pointOnSide(w: World, side: Side, t: f32) Vec2 {
    const r = w.config.enemy.radius;
    const width = w.config.world.width;
    const height = w.config.world.height;
    const along_x = r + t * (width - r - r);
    const along_y = r + t * (height - r - r);
    return switch (side) {
        .left => .{ r, along_y },
        .right => .{ width - r, along_y },
        .top => .{ along_x, r },
        .bottom => .{ along_x, height - r },
    };
}

const config_example = @import("../config.zig").example;

test "update: nada antes do intervalo da onda; um inimigo quando ele passa" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // onda 1: 2 inimigos, a cada 1 s
    defer w.deinit(gpa);
    try update(&w, gpa, 0.5);
    try std.testing.expectEqual(0, w.enemies.count);
    try update(&w, gpa, 0.5);
    try std.testing.expectEqual(1, w.enemies.count);
    try std.testing.expectEqual(1, w.wave_spawned);
    try std.testing.expectEqual(w.config.enemy.life, w.enemies.items.items(.health)[0].current);
}

test "update: um passo longo cria vários, mas nunca mais que os inimigos da onda" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example());
    defer w.deinit(gpa);
    try update(&w, gpa, 10);
    try std.testing.expectEqual(2, w.enemies.count);
    try update(&w, gpa, 10);
    try std.testing.expectEqual(2, w.enemies.count);
}

test "update: na pausa entre ondas não nasce ninguém; depois, nasce no ritmo da onda nova" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // onda 2: 3 inimigos, a cada 0.5 s
    defer w.deinit(gpa);
    w.wave = 1;
    w.wave_break = 1;
    w.spawn_timer = 0.5;
    try update(&w, gpa, 0.75);
    try std.testing.expectEqual(0, w.enemies.count);
    try std.testing.expectEqual(0.25, w.wave_break);
    try update(&w, gpa, 0.25);
    try std.testing.expectEqual(0, w.wave_break);
    try std.testing.expectEqual(0, w.enemies.count);
    try update(&w, gpa, 0.5);
    try std.testing.expectEqual(1, w.enemies.count);
}

test "update: nasce encostado numa borda, dentro do mundo, e usa os quatro lados" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // mundo 800x600, raio do inimigo 10
    defer w.deinit(gpa);
    w.config.waves = .{ .break_time = 0, .waves = &.{.{ .enemies = 40, .interval = 1 }} };
    var seen: [4]bool = @splat(false);
    for (0..40) |_| try update(&w, gpa, 1);
    try std.testing.expectEqual(40, w.enemies.count);
    for (w.enemies.items.items(.pos)) |p| {
        try std.testing.expect(p[0] >= 10 and p[0] <= 790 and p[1] >= 10 and p[1] <= 590);
        if (p[0] == 10) seen[0] = true;
        if (p[0] == 790) seen[1] = true;
        if (p[1] == 10) seen[2] = true;
        if (p[1] == 590) seen[3] = true;
    }
    try std.testing.expect(seen[0] and seen[1] and seen[2] and seen[3]);
}

test "pointOnSide: t = 0 e t = 1 dão os cantos, sem sair do mundo pelo raio" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // mundo 800x600, raio 10
    defer w.deinit(gpa);
    try expectVec(.{ 10, 10 }, pointOnSide(w, .left, 0));
    try expectVec(.{ 10, 590 }, pointOnSide(w, .left, 1));
    try expectVec(.{ 790, 590 }, pointOnSide(w, .right, 1));
    try expectVec(.{ 790, 10 }, pointOnSide(w, .top, 1));
    try expectVec(.{ 10, 590 }, pointOnSide(w, .bottom, 0));
    try expectVec(.{ 790, 590 }, pointOnSide(w, .bottom, 1));
}
