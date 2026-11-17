//! Sistema `contato`: inimigo encostando na líder ou num patinho vira um
//! evento de dano na fila, que depois fica invulnerável por um tempo.
const std = @import("std");
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;

pub fn update(w: *World, gpa: std.mem.Allocator, dt: f32) !void {
    w.invulnerable = @max(w.invulnerable - dt, 0);
    if (w.invulnerable > 0 or !anyContact(w.*)) return;
    try w.events.append(gpa, .{ .damage = .{ .target = .queue, .amount = w.config.enemy.contact_damage } });
    w.invulnerable = w.config.queue.invulnerable_time;
}

fn anyContact(w: World) bool {
    const enemy_r = w.config.enemy.radius;
    for (w.enemies.items.items(.pos), 0..) |pos, i| {
        if (!w.enemies.isAlive(i)) continue;
        if (touches(pos, w.leader.pos, enemy_r + w.config.leader.radius)) return true;
        for (w.ducks.items(.pos)) |duck| {
            if (touches(pos, duck, enemy_r + w.config.queue.radius)) return true;
        }
    }
    return false;
}

fn touches(a: Vec2, b: Vec2, reach: f32) bool {
    return vec.length(a - b) <= reach;
}

const config_example = @import("../config.zig").example;

/// Exemplo: líder em (400, 300) raio 12; patinhos raio 10 em (374, 300)...;
/// inimigo raio 10; dano de contato 2; invulnerável por 1 s.
fn worldWithEnemy(gpa: std.mem.Allocator, pos: Vec2) !World {
    var w: World = try .init(gpa, config_example());
    _ = try w.enemies.add(gpa, .{ .pos = pos, .health = .init(1) });
    return w;
}

fn expectQueueDamage(w: World, count: usize) !void {
    try std.testing.expectEqual(count, w.events.items.len);
    for (w.events.items) |e| {
        try std.testing.expectEqual(.queue, std.meta.activeTag(e.damage.target));
        try std.testing.expectEqual(w.config.enemy.contact_damage, e.damage.amount);
    }
}

test "update: encostar na líder (distância igual à soma dos raios) gera dano e invulnerabilidade" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 422, 300 });
    defer w.deinit(gpa);
    try update(&w, gpa, 0);
    try expectQueueDamage(w, 1);
    try std.testing.expectEqual(w.config.queue.invulnerable_time, w.invulnerable);
}

test "update: encostar num patinho também gera dano" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 374, 320 });
    defer w.deinit(gpa);
    try update(&w, gpa, 0);
    try expectQueueDamage(w, 1);
}

test "update: um pouco longe da líder e dos patinhos, nada" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 422.5, 300 });
    defer w.deinit(gpa);
    try update(&w, gpa, 0);
    try expectQueueDamage(w, 0);
}

test "update: invulnerável não leva dano; depois do tempo, leva de novo" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 400, 300 });
    defer w.deinit(gpa);
    try update(&w, gpa, 0);
    try update(&w, gpa, 0.5);
    try expectQueueDamage(w, 1);
    try update(&w, gpa, 0.5);
    try expectQueueDamage(w, 2);
}

test "update: dois inimigos encostando no mesmo passo dão um dano só" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 400, 300 });
    defer w.deinit(gpa);
    _ = try w.enemies.add(gpa, .{ .pos = .{ 374, 300 }, .health = .init(1) });
    try update(&w, gpa, 0);
    try expectQueueDamage(w, 1);
}

test "update: inimigo removido não encosta" {
    const gpa = std.testing.allocator;
    var w = try worldWithEnemy(gpa, .{ 400, 300 });
    defer w.deinit(gpa);
    w.enemies.remove(w.enemies.handleAt(0));
    try update(&w, gpa, 0);
    try expectQueueDamage(w, 0);
}
