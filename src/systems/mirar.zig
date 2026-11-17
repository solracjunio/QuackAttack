//! Sistema `mirar`: cada patinho de ataque à distância mantém um alvo
//! `(Mira, inimigo)`. Fica com o mesmo enquanto ele viver e estiver no
//! alcance; senão, mira no inimigo vivo mais próximo do alcance.
const std = @import("std");
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;
const Handle = @import("../pool.zig").Handle;
const Entity = @import("../relations.zig").Entity;

pub fn update(w: *World, gpa: std.mem.Allocator) !void {
    const ducks = w.ducks.slice();
    for (ducks.items(.pos), ducks.items(.class), 0..) |pos, class, i| {
        const range = switch (w.config.classes[class].attack) {
            .projectile => |a| a.range,
            else => continue,
        };
        const me: Entity = .{ .duck = @intCast(i) };
        if (keepsTarget(w.*, me, pos, range)) continue;
        if (nearestEnemy(w.*, pos, range)) |h| {
            try w.relations.set(gpa, .mira, me, .{ .enemy = h });
        } else {
            w.relations.clear(.mira, me);
        }
    }
}

/// O alvo atual ainda vive e está no alcance?
fn keepsTarget(w: World, me: Entity, pos: Vec2, range: f32) bool {
    const target = w.relations.targetOf(.mira, me) orelse return false;
    const s = w.enemies.slot(target.enemy) orelse return false;
    return vec.length(w.enemies.items.items(.pos)[s] - pos) <= range;
}

/// Inimigo vivo mais próximo de `from`, até `range` de distância.
fn nearestEnemy(w: World, from: Vec2, range: f32) ?Handle {
    var best: ?Handle = null;
    var best_dist = range;
    for (w.enemies.items.items(.pos), 0..) |pos, i| {
        if (!w.enemies.isAlive(i)) continue;
        const dist = vec.length(pos - from);
        if (dist <= best_dist) {
            best = w.enemies.handleAt(i);
            best_dist = dist;
        }
    }
    return best;
}

const config_example = @import("../config.zig").example;

/// Exemplo: patinho 0 é arqueiro (alcance 200) e patinho 2 é mago; nos testes,
/// os dois ficam em (100, 100) e o outro arqueiro, longe.
/// Mundo do exemplo com os três patinhos (arqueiro, arqueiro, mago) em `ducks`.
fn withDucks(gpa: std.mem.Allocator, ducks: []const Vec2) !World {
    var w: World = try .init(gpa, config_example());
    @memcpy(w.ducks.items(.pos), ducks);
    return w;
}

fn enemyAt(w: *World, gpa: std.mem.Allocator, pos: Vec2) !Handle {
    return w.enemies.add(gpa, .{ .pos = pos, .health = .init(1) });
}

fn aim(w: World) ?Handle {
    const t = w.relations.targetOf(.mira, .{ .duck = 0 }) orelse return null;
    return t.enemy;
}

test "update: sem inimigo no alcance, sem alvo" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    _ = try enemyAt(&w, gpa, .{ 300.5, 100 });
    try update(&w, gpa);
    try std.testing.expectEqual(null, aim(w));
}

test "update: inimigo exatamente no limite do alcance conta" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    const edge = try enemyAt(&w, gpa, .{ 300, 100 });
    try update(&w, gpa);
    try std.testing.expectEqual(edge, aim(w).?);
}

test "update: mira no inimigo mais próximo do alcance" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    _ = try enemyAt(&w, gpa, .{ 100, 300 });
    const near = try enemyAt(&w, gpa, .{ 100, 250 });
    try update(&w, gpa);
    try std.testing.expectEqual(near, aim(w).?);
}

test "update: mantém o alvo enquanto ele está no alcance, mesmo com outro mais perto" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    const first = try enemyAt(&w, gpa, .{ 100, 250 });
    try update(&w, gpa);
    _ = try enemyAt(&w, gpa, .{ 100, 120 });
    try update(&w, gpa);
    try std.testing.expectEqual(first, aim(w).?);
}

test "update: troca de alvo quando o atual sai do alcance" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    const first = try enemyAt(&w, gpa, .{ 100, 250 });
    const second = try enemyAt(&w, gpa, .{ 100, 280 });
    try update(&w, gpa);
    w.enemies.items.items(.pos)[w.enemies.slot(first).?] = .{ 100, 301 };
    try update(&w, gpa);
    try std.testing.expectEqual(second, aim(w).?);
}

test "update: alvo removido (handle velho) e ninguém no alcance: fica sem alvo" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    const first = try enemyAt(&w, gpa, .{ 100, 250 });
    try update(&w, gpa);
    w.enemies.remove(first);
    _ = try enemyAt(&w, gpa, .{ 100, 400 }); // mesma vaga, fora do alcance
    try update(&w, gpa);
    try std.testing.expectEqual(null, aim(w));
}

test "update: patinho de ataque em área não mira" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    _ = try enemyAt(&w, gpa, .{ 100, 120 });
    try update(&w, gpa);
    try std.testing.expectEqual(null, w.relations.targetOf(.mira, .{ .duck = 2 }));
}

test "update: alvo atual exatamente no limite do alcance continua sendo o alvo" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    const first = try enemyAt(&w, gpa, .{ 100, 250 });
    try update(&w, gpa);
    w.enemies.items.items(.pos)[w.enemies.slot(first).?] = .{ 100, 300 };
    _ = try enemyAt(&w, gpa, .{ 100, 120 });
    try update(&w, gpa);
    try std.testing.expectEqual(first, aim(w).?);
}
