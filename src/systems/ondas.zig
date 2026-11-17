//! Sistema `ondas`: quando a onda já soltou todos os inimigos e nenhum está
//! vivo, ela acaba. Um patinho novo, de classe sorteada, entra no fim da fila,
//! e a próxima onda começa depois da pausa.
const std = @import("std");
const World = @import("../world.zig").World;
const waves = @import("../waves.zig");

pub fn update(w: *World, gpa: std.mem.Allocator) !void {
    // Na pausa, a onda nova ainda não soltou ninguém (e toda onda tem ao
    // menos um inimigo): ela não "acaba" de novo, sem precisar de guarda.
    const cfg = w.config;
    const wave = waves.at(cfg.waves, w.wave);
    if (w.wave_spawned < wave.enemies or w.enemies.count > 0) return;

    try w.events.append(gpa, .{ .wave_ended = .{ .wave = w.wave + 1 } });
    const class = w.rng.random().uintLessThan(u32, @intCast(cfg.classes.len));
    try w.addDuck(gpa, class);
    try w.events.append(gpa, .{ .duck_joined = .{ .duck = @intCast(w.ducks.len - 1), .class = class } });

    w.wave += 1;
    w.wave_spawned = 0;
    w.wave_break = cfg.waves.break_time;
    w.spawn_timer = waves.at(cfg.waves, w.wave).interval;
}

const config_example = @import("../config.zig").example;

test "update: a onda não acaba enquanto falta inimigo nascer ou algum está vivo" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // onda 1: 2 inimigos
    defer w.deinit(gpa);
    w.wave_spawned = 1;
    try update(&w, gpa);
    try std.testing.expectEqual(0, w.events.items.len);
    w.wave_spawned = 2;
    _ = try w.enemies.add(gpa, .{ .pos = .{ 0, 0 }, .health = .init(1) });
    try update(&w, gpa);
    try std.testing.expectEqual(0, w.events.items.len);
}

test "update: fim da onda: eventos, patinho novo seguindo a líder e próxima onda depois da pausa" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // 3 patinhos; pausa 2; onda 2 a cada 0.5 s
    defer w.deinit(gpa);
    w.wave_spawned = 2;
    try update(&w, gpa);
    try std.testing.expectEqual(1, w.events.items[0].wave_ended.wave);
    const joined = w.events.items[1].duck_joined;
    try std.testing.expectEqual(3, joined.duck);
    try std.testing.expectEqual(4, w.ducks.len);
    try std.testing.expectEqual(joined.class, w.ducks.items(.class)[3]);
    try std.testing.expect(w.relations.targetOf(.segue, .{ .duck = 3 }) != null);
    try std.testing.expectEqual(1, w.wave);
    try std.testing.expectEqual(0, w.wave_spawned);
    try std.testing.expectEqual(2, w.wave_break);
    try std.testing.expectEqual(0.5, w.spawn_timer);
}

test "update: na pausa, a onda que acabou não acaba de novo" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example());
    defer w.deinit(gpa);
    w.wave_spawned = 2;
    try update(&w, gpa);
    try update(&w, gpa);
    var ended: usize = 0;
    for (w.events.items) |e| {
        if (e == .wave_ended) ended += 1;
    }
    try std.testing.expectEqual(1, ended);
}

test "update: a classe sorteada é sempre uma que existe, e todas aparecem" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // 2 classes
    defer w.deinit(gpa);
    var seen: [2]bool = @splat(false);
    for (0..20) |_| {
        w.wave_spawned = waves.at(w.config.waves, w.wave).enemies;
        w.wave_break = 0;
        w.events.clearRetainingCapacity();
        try update(&w, gpa);
        seen[w.events.items[1].duck_joined.class] = true;
    }
    try std.testing.expect(seen[0] and seen[1]);
}
