//! Sistema `magia`: cada patinho de ataque em área, quando a recarga acaba e
//! há inimigos dentro do raio, gera um evento de dano para cada um deles.
const std = @import("std");
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;
const Handle = @import("../pool.zig").Handle;

pub fn update(w: *World, gpa: std.mem.Allocator, dt: f32) !void {
    const ducks = w.ducks.slice();
    for (ducks.items(.pos), ducks.items(.cooldown), ducks.items(.class)) |pos, *cooldown, class| {
        const spell = switch (w.config.classes[class].attack) {
            .area => |a| a,
            else => continue,
        };
        cooldown.* = @max(cooldown.* - dt, 0);
        if (cooldown.* > 0) continue;
        if (try hitAround(w, gpa, pos, spell.radius, spell.damage) > 0) cooldown.* = spell.cooldown;
    }
}

/// Um evento de dano para cada inimigo vivo a até `radius` de `center`.
/// Devolve quantos foram atingidos.
fn hitAround(w: *World, gpa: std.mem.Allocator, center: Vec2, radius: f32, damage: u32) !usize {
    var hit: usize = 0;
    for (w.enemies.items.items(.pos), 0..) |pos, i| {
        if (!w.enemies.isAlive(i) or vec.length(pos - center) > radius) continue;
        const target: Handle = w.enemies.handleAt(i);
        try w.events.append(gpa, .{ .damage = .{ .target = .{ .enemy = target }, .amount = damage } });
        hit += 1;
    }
    return hit;
}

const config_example = @import("../config.zig").example;

/// Exemplo: patinho 2 é mago (raio 60, recarga 1, dano 2); nos testes, ele
/// fica em (100, 100) e os arqueiros, longe.
/// Mundo do exemplo com os três patinhos (arqueiro, arqueiro, mago) em `ducks`.
fn withDucks(gpa: std.mem.Allocator, ducks: []const Vec2) !World {
    var w: World = try .init(gpa, config_example());
    @memcpy(w.ducks.items(.pos), ducks);
    return w;
}

fn enemyAt(w: *World, gpa: std.mem.Allocator, pos: Vec2) !Handle {
    return w.enemies.add(gpa, .{ .pos = pos, .health = .init(w.config.enemy.life) });
}

test "update: sem inimigo no raio, não lança e fica pronto" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 5000, 5000 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    _ = try enemyAt(&w, gpa, .{ 160.5, 100 });
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(0, w.events.items.len);
    try std.testing.expectEqual(0, w.ducks.items(.cooldown)[2]);
}

test "update: acerta todos dentro do raio (a borda conta), com o dano da classe" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 5000, 5000 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    const a = try enemyAt(&w, gpa, .{ 100, 140 });
    _ = try enemyAt(&w, gpa, .{ 100, 161 }); // fora
    const b = try enemyAt(&w, gpa, .{ 160, 100 }); // na borda
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(2, w.events.items.len);
    try std.testing.expectEqual(a, w.events.items[0].damage.target.enemy);
    try std.testing.expectEqual(b, w.events.items[1].damage.target.enemy);
    for (w.events.items) |e| try std.testing.expectEqual(2, e.damage.amount);
    try std.testing.expectEqual(1, w.ducks.items(.cooldown)[2]);
}

test "update: espera a recarga para lançar de novo" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 5000, 5000 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    _ = try enemyAt(&w, gpa, .{ 100, 120 });
    try update(&w, gpa, 0.5);
    try update(&w, gpa, 0.5); // recarga 1: falta 0.5
    try std.testing.expectEqual(1, w.events.items.len);
    try update(&w, gpa, 0.5);
    try std.testing.expectEqual(2, w.events.items.len);
}

test "update: arqueiro não lança magia" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 5000, 5000 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    w.ducks.items(.pos)[0] = .{ 100, 100 };
    w.ducks.items(.pos)[2] = .{ 5000, 5000 };
    _ = try enemyAt(&w, gpa, .{ 100, 120 });
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(0, w.events.items.len);
}

test "update: ignora inimigo removido" {
    const gpa = std.testing.allocator;
    var w = try withDucks(gpa, &.{ .{ 5000, 5000 }, .{ 5000, 5000 }, .{ 100, 100 } });
    defer w.deinit(gpa);
    const h = try enemyAt(&w, gpa, .{ 100, 120 });
    w.enemies.remove(h);
    try update(&w, gpa, 0.1);
    try std.testing.expectEqual(0, w.events.items.len);
}
