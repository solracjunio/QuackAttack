//! Sistema `atacar`: cada patinho (arqueiro, por enquanto) atira no inimigo
//! vivo mais próximo dentro do alcance, quando o tempo de recarga acaba.
const std = @import("std");
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;
const expectVec = @import("../testing.zig").expectVec;

pub fn update(w: *World, gpa: std.mem.Allocator, dt: f32) !void {
    const archer = w.config.archer;
    const ducks = w.ducks.slice();
    for (ducks.items(.pos), ducks.items(.cooldown)) |pos, *cooldown| {
        cooldown.* = @max(cooldown.* - dt, 0);
        if (cooldown.* > 0) continue;
        const target = nearestEnemy(w.*, pos, archer.range) orelse continue;
        _ = try w.projectiles.add(gpa, .{
            .pos = pos,
            .velocity = vec.scale(aim(w.*, pos, target), w.config.projectile.speed),
            .remaining = archer.range,
        });
        cooldown.* = archer.cooldown;
    }
}

/// Posição do inimigo vivo mais próximo de `from`, até `range` de distância.
fn nearestEnemy(w: World, from: Vec2, range: f32) ?Vec2 {
    var best: ?Vec2 = null;
    var best_dist = range;
    for (w.enemies.items.items(.pos), 0..) |pos, i| {
        if (!w.enemies.isAlive(i)) continue;
        const dist = vec.length(pos - from);
        if (dist <= best_dist) {
            best = pos;
            best_dist = dist;
        }
    }
    return best;
}

/// Direção unitária de `from` para `target`. Em cima do alvo, usa a direção da líder.
fn aim(w: World, from: Vec2, target: Vec2) Vec2 {
    const to_target = target - from;
    if (vec.length(to_target) == 0) return w.leader.heading;
    return vec.normalize(to_target);
}

const config_example = @import("../config.zig").example;

/// Mundo do exemplo com um patinho só, em `duck`. Alcance 200, recarga 0.5,
/// flecha com speed 400.
fn oneDuckAt(gpa: std.mem.Allocator, duck: Vec2) !World {
    var w: World = try .init(gpa, config_example());
    w.ducks.shrinkRetainingCapacity(1);
    w.ducks.items(.pos)[0] = duck;
    return w;
}

test "update: sem inimigo, não atira" {
    const gpa = std.testing.allocator;
    var w = try oneDuckAt(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(0, w.projectiles.count);
}

test "update: atira no inimigo do alcance e recomeça a recarga" {
    const gpa = std.testing.allocator;
    var w = try oneDuckAt(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    _ = try w.enemies.add(gpa, .{ .pos = .{ 100, 250 }, .health = .init(1) });
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(1, w.projectiles.count);
    const p = w.projectiles.items;
    try expectVec(.{ 100, 100 }, p.items(.pos)[0]);
    try expectVec(.{ 0, 400 }, p.items(.velocity)[0]);
    try std.testing.expectEqual(200, p.items(.remaining)[0]);
    try std.testing.expectEqual(0.5, w.ducks.items(.cooldown)[0]);
}

test "update: alcance inclui a distância exata; um pouco além, não atira" {
    const gpa = std.testing.allocator;
    var w = try oneDuckAt(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    const far = try w.enemies.add(gpa, .{ .pos = .{ 300.5, 100 }, .health = .init(1) });
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(0, w.projectiles.count);
    w.enemies.remove(far);
    _ = try w.enemies.add(gpa, .{ .pos = .{ 300, 100 }, .health = .init(1) });
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(1, w.projectiles.count);
}

test "update: entre dois inimigos, mira no mais próximo" {
    const gpa = std.testing.allocator;
    var w = try oneDuckAt(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    _ = try w.enemies.add(gpa, .{ .pos = .{ 100, 250 }, .health = .init(1) });
    _ = try w.enemies.add(gpa, .{ .pos = .{ 50, 100 }, .health = .init(1) });
    _ = try w.enemies.add(gpa, .{ .pos = .{ 100, 200 }, .health = .init(1) });
    try update(&w, gpa, 0.1);
    try expectVec(.{ -400, 0 }, w.projectiles.items.items(.velocity)[0]);
}

test "update: espera a recarga para atirar de novo" {
    const gpa = std.testing.allocator;
    var w = try oneDuckAt(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    _ = try w.enemies.add(gpa, .{ .pos = .{ 100, 150 }, .health = .init(1) });
    try update(&w, gpa, 0.25);
    try update(&w, gpa, 0.25); // recarga 0.5: falta 0.25
    try std.testing.expectEqual(1, w.projectiles.count);
    try update(&w, gpa, 0.25);
    try std.testing.expectEqual(2, w.projectiles.count);
}

test "update: ignora inimigo removido" {
    const gpa = std.testing.allocator;
    var w = try oneDuckAt(gpa, .{ 100, 100 });
    defer w.deinit(gpa);
    const h = try w.enemies.add(gpa, .{ .pos = .{ 100, 150 }, .health = .init(1) });
    w.enemies.remove(h);
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(0, w.projectiles.count);
}

test "update: inimigo em cima do patinho, atira na direção da líder (sem NaN)" {
    const gpa = std.testing.allocator;
    var w = try oneDuckAt(gpa, .{ 100, 100 }); // líder olhando para +x
    defer w.deinit(gpa);
    _ = try w.enemies.add(gpa, .{ .pos = .{ 100, 100 }, .health = .init(1) });
    try update(&w, gpa, 0.1);
    try expectVec(.{ 400, 0 }, w.projectiles.items.items(.velocity)[0]);
}
