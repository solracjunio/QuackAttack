//! Sistema `perseguir`: cada inimigo anda em direção à líder.
const std = @import("std");
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;
const expectVec = @import("../testing.zig").expectVec;

pub fn update(w: *World, dt: f32) void {
    const step = w.config.enemy.speed * dt;
    const target = w.leader.pos;
    const positions = w.enemies.items.items(.pos);
    for (positions, 0..) |*pos, i| {
        if (!w.enemies.isAlive(i)) continue;
        const to_target = target - pos.*;
        const dist = vec.length(to_target);
        // Mais perto que um passo: chega na líder (também evita dividir por 0).
        // mutation: disable — com dist == step, andar um passo também chega exatamente na líder
        const arrives = dist <= step;
        if (arrives) {
            pos.* = target;
        } else {
            pos.* += vec.scale(to_target, step / dist);
        }
    }
}

const config_example = @import("../config.zig").example;

fn worldWithEnemy(gpa: std.mem.Allocator, pos: Vec2) !World {
    var w: World = try .init(gpa, config_example()); // líder em (400, 300), inimigo com speed 60
    _ = try w.enemies.add(gpa, .{ .pos = pos, .health = .init(1) });
    return w;
}

test "update: anda `speed * dt` em direção à líder" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 100, 300 });
    defer w.deinit(gpa);
    update(&w, 0.5);
    try expectVec(.{ 130, 300 }, w.enemies.items.items(.pos)[0]);
}

test "update: perto da líder, para nela em vez de passar do ponto" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 390, 300 });
    defer w.deinit(gpa);
    update(&w, 0.5);
    try expectVec(.{ 400, 300 }, w.enemies.items.items(.pos)[0]);
}

test "update: já em cima da líder, fica parado (sem NaN)" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 400, 300 });
    defer w.deinit(gpa);
    update(&w, 0.5);
    try expectVec(.{ 400, 300 }, w.enemies.items.items(.pos)[0]);
}

test "update: inimigo removido não anda" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 100, 300 });
    defer w.deinit(gpa);
    w.enemies.remove(w.enemies.handleAt(0));
    update(&w, 0.5);
    try expectVec(.{ 100, 300 }, w.enemies.items.items(.pos)[0]);
}
