//! Sistema `atacar`: cada patinho de ataque à distância atira no inimigo que
//! está mirando `(Mira, inimigo)`, com os números da classe dele, quando o
//! tempo de recarga acaba. Escolher o alvo é do sistema `mirar`.
const std = @import("std");
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;
const expectVec = @import("../testing.zig").expectVec;
const Handle = @import("../pool.zig").Handle;

pub fn update(w: *World, gpa: std.mem.Allocator, dt: f32) !void {
    const ducks = w.ducks.slice();
    for (ducks.items(.pos), ducks.items(.cooldown), ducks.items(.class), 0..) |pos, *cooldown, class, i| {
        const arrow = switch (w.config.classes[class].attack) {
            .projectile => |a| a,
            else => continue,
        };
        cooldown.* = @max(cooldown.* - dt, 0);
        if (cooldown.* > 0) continue;
        const target = targetPos(w.*, @intCast(i)) orelse continue;
        _ = try w.projectiles.add(gpa, .{
            .pos = pos,
            .velocity = vec.scale(aim(w.*, pos, target), arrow.speed),
            .remaining = arrow.range,
            .damage = arrow.damage,
            .radius = arrow.radius,
        });
        cooldown.* = arrow.cooldown;
    }
}

/// Posição do inimigo que o patinho `duck` mira, se ele ainda existir.
fn targetPos(w: World, duck: u32) ?Vec2 {
    const target = w.relations.targetOf(.mira, .{ .duck = duck }) orelse return null;
    const s = w.enemies.slot(target.enemy) orelse return null;
    return w.enemies.items.items(.pos)[s];
}

/// Direção unitária de `from` para `target`. Em cima do alvo, usa a direção da líder.
fn aim(w: World, from: Vec2, target: Vec2) Vec2 {
    const to_target = target - from;
    if (vec.length(to_target) == 0) return w.leader.heading;
    return vec.normalize(to_target);
}

const config_example = @import("../config.zig").example;

/// Exemplo: patinho 0 é arqueiro (alcance 200, recarga 0.5, flecha 400/s,
/// dano 1, raio 4) e patinho 2 é mago; nos testes, os dois ficam em (100, 100).
/// Mundo do exemplo com os três patinhos (arqueiro, arqueiro, mago) em `ducks`.
fn withDucks(gpa: std.mem.Allocator, ducks: []const Vec2) !World {
    var w: World = try .init(gpa, config_example());
    @memcpy(w.ducks.items(.pos), ducks);
    return w;
}

/// Inimigo em `pos`, já mirado pelo patinho 0.
fn aimedEnemy(w: *World, gpa: std.mem.Allocator, pos: Vec2) !Handle {
    const h = try w.enemies.add(gpa, .{ .pos = pos, .health = .init(1) });
    try w.relations.set(gpa, .mira, .{ .duck = 0 }, .{ .enemy = h });
    return h;
}

test "update: sem alvo, não atira" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    _ = try w.enemies.add(gpa, .{ .pos = .{ 100, 150 }, .health = .init(1) });
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(0, w.projectiles.count);
}

test "update: atira no alvo com os números da classe e recomeça a recarga" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    _ = try aimedEnemy(&w, gpa, .{ 100, 250 });
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(1, w.projectiles.count);
    const p = w.projectiles.items;
    try expectVec(.{ 100, 100 }, p.items(.pos)[0]);
    try expectVec(.{ 0, 400 }, p.items(.velocity)[0]);
    try std.testing.expectEqual(200, p.items(.remaining)[0]);
    try std.testing.expectEqual(1, p.items(.damage)[0]);
    try std.testing.expectEqual(4, p.items(.radius)[0]);
    try std.testing.expectEqual(0.5, w.ducks.items(.cooldown)[0]);
}

test "update: espera a recarga para atirar de novo" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    _ = try aimedEnemy(&w, gpa, .{ 100, 150 });
    try update(&w, gpa, 0.25);
    try update(&w, gpa, 0.25); // recarga 0.5: falta 0.25
    try std.testing.expectEqual(1, w.projectiles.count);
    try update(&w, gpa, 0.25);
    try std.testing.expectEqual(2, w.projectiles.count);
}

test "update: alvo removido (handle velho) não recebe tiro" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    const h = try aimedEnemy(&w, gpa, .{ 100, 150 });
    w.enemies.remove(h);
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(0, w.projectiles.count);
}

test "update: patinho de ataque em área não atira, mesmo mirando" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    const h = try w.enemies.add(gpa, .{ .pos = .{ 100, 150 }, .health = .init(1) });
    try w.relations.set(gpa, .mira, .{ .duck = 2 }, .{ .enemy = h });
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(0, w.projectiles.count);
}

test "update: alvo em cima do patinho, atira na direção da líder (sem NaN)" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 100, 100 }, .{ 5000, 5000 }, .{ 100, 100 } }); // líder olhando para +x
    defer w.deinit(gpa);
    _ = try aimedEnemy(&w, gpa, .{ 100, 100 });
    try update(&w, gpa, 0.1);
    try expectVec(.{ 400, 0 }, w.projectiles.items.items(.velocity)[0]);
}
