//! Sistema `aplicar_dano`: aplica os eventos de dano do passo. Inimigo que
//! chega a 0 de vida vira um evento `died` (um só, mesmo com vários golpes).
const std = @import("std");
const World = @import("../world.zig").World;
const Handle = @import("../pool.zig").Handle;

pub fn update(w: *World, gpa: std.mem.Allocator) !void {
    // Por índice: os `died` acrescentados aqui entram no fim da mesma lista.
    var i: usize = 0;
    while (i < w.events.items.len) : (i += 1) {
        const d = switch (w.events.items[i]) {
            .damage => |d| d,
            else => continue,
        };
        switch (d.target) {
            .queue => w.queue_health.damage(d.amount),
            .enemy => |h| try damageEnemy(w, gpa, h, d.amount),
        }
    }
}

fn damageEnemy(w: *World, gpa: std.mem.Allocator, h: Handle, amount: u32) !void {
    const s = w.enemies.slot(h) orelse return;
    const health = &w.enemies.items.items(.health)[s];
    if (health.isDead()) return;
    health.damage(amount);
    if (health.isDead()) try w.events.append(gpa, .{ .died = .{ .enemy = h } });
}

const config_example = @import("../config.zig").example;

fn worldWithEnemy(gpa: std.mem.Allocator, life: u32) !struct { World, Handle } {
    var w: World = try .init(gpa, config_example()); // fila com 10 de vida
    const h = try w.enemies.add(gpa, .{ .pos = .{ 0, 0 }, .health = .init(life) });
    return .{ w, h };
}

fn hit(w: *World, gpa: std.mem.Allocator, h: Handle, amount: u32) !void {
    try w.events.append(gpa, .{ .damage = .{ .target = .{ .enemy = h }, .amount = amount } });
}

fn diedCount(w: World) usize {
    var n: usize = 0;
    for (w.events.items) |e| {
        if (e == .died) n += 1;
    }
    return n;
}

test "update: dano na fila tira da vida da fila" {
    const gpa = std.testing.allocator;
    var w, _ = try worldWithEnemy(gpa, 3);
    defer w.deinit(gpa);
    try w.events.append(gpa, .{ .damage = .{ .target = .queue, .amount = 4 } });
    try update(&w, gpa);
    try std.testing.expectEqual(6, w.queue_health.current);
}

test "update: dano no inimigo tira da vida dele, sem morrer" {
    const gpa = std.testing.allocator;
    var w, const h = try worldWithEnemy(gpa, 3);
    defer w.deinit(gpa);
    try hit(&w, gpa, h, 2);
    try update(&w, gpa);
    try std.testing.expectEqual(1, w.enemies.items.items(.health)[w.enemies.slot(h).?].current);
    try std.testing.expectEqual(0, diedCount(w));
}

test "update: dano mortal gera um evento died com o handle do inimigo" {
    const gpa = std.testing.allocator;
    var w, const h = try worldWithEnemy(gpa, 3);
    defer w.deinit(gpa);
    try hit(&w, gpa, h, 3);
    try update(&w, gpa);
    try std.testing.expectEqual(1, diedCount(w));
    try std.testing.expectEqual(h, w.events.items[1].died.enemy);
}

test "update: dois golpes mortais no mesmo passo geram um died só" {
    const gpa = std.testing.allocator;
    var w, const h = try worldWithEnemy(gpa, 1);
    defer w.deinit(gpa);
    try hit(&w, gpa, h, 1);
    try hit(&w, gpa, h, 1);
    try update(&w, gpa);
    try std.testing.expectEqual(1, diedCount(w));
}

test "update: handle de inimigo já removido é ignorado" {
    const gpa = std.testing.allocator;
    var w, const h = try worldWithEnemy(gpa, 3);
    defer w.deinit(gpa);
    w.enemies.remove(h);
    const other = try w.enemies.add(gpa, .{ .pos = .{ 0, 0 }, .health = .init(3) }); // mesma vaga
    try hit(&w, gpa, h, 2);
    try update(&w, gpa);
    try std.testing.expectEqual(3, w.enemies.items.items(.health)[w.enemies.slot(other).?].current);
    try std.testing.expectEqual(0, diedCount(w));
}
