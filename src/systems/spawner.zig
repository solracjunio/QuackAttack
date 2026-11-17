//! Sistema `spawner`: a cada intervalo, um inimigo novo num ponto aleatório
//! da borda do mundo (lado e posição vêm do gerador com a seed).
const std = @import("std");
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;
const expectVec = @import("../testing.zig").expectVec;

const Side = enum { left, right, top, bottom };

pub fn update(w: *World, gpa: std.mem.Allocator, dt: f32) !void {
    w.spawn_timer -= dt;
    while (w.spawn_timer <= 0) : (w.spawn_timer += w.config.spawner.interval) {
        _ = try w.enemies.add(gpa, .{ .pos = borderPoint(w), .health = .init(w.config.enemy.life) });
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

test "update: nada antes do intervalo; um inimigo quando o intervalo passa" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // intervalo 2
    defer w.deinit(gpa);
    // 1.5 + 0.5: valores exatos em binário (1.9 + 0.1 em f32 não fecha em 2).
    try update(&w, gpa, 1.5);
    try std.testing.expectEqual(0, w.enemies.count);
    try update(&w, gpa, 0.5);
    try std.testing.expectEqual(1, w.enemies.count);
    try std.testing.expectEqual(w.config.enemy.life, w.enemies.items.items(.health)[0].current);
}

test "update: um passo longo que cobre dois intervalos cria dois inimigos" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example());
    defer w.deinit(gpa);
    try update(&w, gpa, 4.0);
    try std.testing.expectEqual(2, w.enemies.count);
}

test "update: nasce encostado numa borda, dentro do mundo, e usa os quatro lados" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // mundo 800x600, raio do inimigo 10
    defer w.deinit(gpa);
    var seen: [4]bool = @splat(false);
    for (0..40) |_| try update(&w, gpa, w.config.spawner.interval);
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
