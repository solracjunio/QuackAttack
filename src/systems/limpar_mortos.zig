//! Sistema `limpar_mortos`: tira do pool os inimigos dos eventos `died`.
//! Roda por último, para todos os sistemas do passo verem os mesmos inimigos.
const std = @import("std");
const World = @import("../world.zig").World;

pub fn update(w: *World) void {
    for (w.events.items) |e| switch (e) {
        .died => |d| w.enemies.remove(d.enemy),
        else => {},
    };
}

const config_example = @import("../config.zig").example;

test "update: remove os inimigos dos eventos died e deixa os outros" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example());
    defer w.deinit(gpa);
    const dead = try w.enemies.add(gpa, .{ .pos = .{ 0, 0 }, .health = .init(1) });
    const alive = try w.enemies.add(gpa, .{ .pos = .{ 0, 0 }, .health = .init(1) });
    try w.events.append(gpa, .{ .damage = .{ .target = .queue, .amount = 1 } });
    try w.events.append(gpa, .{ .died = .{ .enemy = dead } });
    update(&w);
    try std.testing.expectEqual(null, w.enemies.slot(dead));
    try std.testing.expect(w.enemies.slot(alive) != null);
}
