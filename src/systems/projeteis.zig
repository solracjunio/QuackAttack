//! Sistema `projeteis`: as flechas voam até o fim do alcance. Ao encostar num
//! inimigo, viram um evento de dano e somem (cada flecha acerta um só).
const std = @import("std");
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;
const Handle = @import("../pool.zig").Handle;
const expectVec = @import("../testing.zig").expectVec;

pub fn update(w: *World, gpa: std.mem.Allocator, dt: f32) !void {
    const p = w.projectiles.items.slice();
    for (0..w.projectiles.slots()) |i| {
        if (!w.projectiles.isAlive(i)) continue;
        p.items(.pos)[i] += vec.scale(p.items(.velocity)[i], dt);
        p.items(.remaining)[i] -= vec.length(p.items(.velocity)[i]) * dt;
        const h = w.projectiles.handleAt(i);
        if (p.items(.remaining)[i] <= 0) {
            w.projectiles.remove(h);
        } else if (touchedEnemy(w.*, p.items(.pos)[i], p.items(.radius)[i])) |enemy| {
            try w.events.append(gpa, .{ .damage = .{ .target = .{ .enemy = enemy }, .amount = p.items(.damage)[i] } });
            w.projectiles.remove(h);
        }
    }
}

/// Primeiro inimigo vivo que encosta numa flecha de raio `radius` em `pos`.
fn touchedEnemy(w: World, pos: Vec2, radius: f32) ?Handle {
    const reach = radius + w.config.enemy.radius;
    for (w.enemies.items.items(.pos), 0..) |enemy_pos, i| {
        if (!w.enemies.isAlive(i)) continue;
        if (vec.length(enemy_pos - pos) <= reach) return w.enemies.handleAt(i);
    }
    return null;
}

const config_example = @import("../config.zig").example;

/// Mundo do exemplo com uma flecha do arqueiro do exemplo em `pos`, indo para
/// +x (400/s, 200 de voo, dano 1). Raio da flecha 4, do inimigo 10: encostam a 14.
fn worldWithArrow(gpa: std.mem.Allocator, pos: Vec2) !World {
    const arrow = @import("../classes.zig").example[0].attack.projectile;
    var w: World = try .init(gpa, config_example());
    _ = try w.projectiles.add(gpa, .{ .pos = pos, .velocity = .{ arrow.speed, 0 }, .remaining = arrow.range, .damage = arrow.damage, .radius = arrow.radius });
    return w;
}

test "update: voa `velocity * dt` e gasta o alcance" {
    const gpa = std.testing.allocator;
    var w = try worldWithArrow(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    try update(&w, gpa, 0.25);
    try expectVec(.{ 200, 100 }, w.projectiles.items.items(.pos)[0]);
    try std.testing.expectEqual(100, w.projectiles.items.items(.remaining)[0]);
}

test "update: some quando o alcance acaba" {
    const gpa = std.testing.allocator;
    var w = try worldWithArrow(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    try update(&w, gpa, 0.25);
    try std.testing.expectEqual(1, w.projectiles.count);
    try update(&w, gpa, 0.25);
    try std.testing.expectEqual(0, w.projectiles.count);
}

test "update: encostar num inimigo gera evento de dano e a flecha some; a vida não muda aqui" {
    const gpa = std.testing.allocator;
    var w = try worldWithArrow(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    const h = try w.enemies.add(gpa, .{ .pos = .{ 114, 100 }, .health = .init(3) });
    try update(&w, gpa, 0);
    try std.testing.expectEqual(0, w.projectiles.count);
    try std.testing.expectEqual(1, w.events.items.len);
    const d = w.events.items[0].damage;
    try std.testing.expectEqual(h, d.target.enemy);
    try std.testing.expectEqual(1, d.amount);
    try std.testing.expectEqual(3, w.enemies.items.items(.health)[0].current);
}

test "update: um pouco longe do inimigo, não acerta" {
    const gpa = std.testing.allocator;
    var w = try worldWithArrow(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    _ = try w.enemies.add(gpa, .{ .pos = .{ 114.5, 100 }, .health = .init(3) });
    try update(&w, gpa, 0);
    try std.testing.expectEqual(1, w.projectiles.count);
    try std.testing.expectEqual(0, w.events.items.len);
}

test "update: com dois inimigos encostados, acerta um só" {
    const gpa = std.testing.allocator;
    var w = try worldWithArrow(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    _ = try w.enemies.add(gpa, .{ .pos = .{ 105, 100 }, .health = .init(3) });
    _ = try w.enemies.add(gpa, .{ .pos = .{ 95, 100 }, .health = .init(3) });
    try update(&w, gpa, 0);
    try std.testing.expectEqual(1, w.events.items.len);
}

test "update: não acerta inimigo removido" {
    const gpa = std.testing.allocator;
    var w = try worldWithArrow(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    const h = try w.enemies.add(gpa, .{ .pos = .{ 105, 100 }, .health = .init(3) });
    w.enemies.remove(h);
    try update(&w, gpa, 0);
    try std.testing.expectEqual(0, w.events.items.len);
    try std.testing.expectEqual(1, w.projectiles.count);
}
