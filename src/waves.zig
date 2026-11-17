//! Ondas de inimigos, lidas de `data/waves.zon`. Depois da última onda, ela
//! se repete: o jogo só acaba quando a vida da fila chega a 0.
const std = @import("std");

pub const Wave = struct {
    /// Quantos inimigos nascem nesta onda.
    enemies: u32,
    /// Segundos entre um inimigo e o próximo.
    interval: f32,
};

pub const Waves = struct {
    /// Segundos de pausa entre o fim de uma onda e o começo da próxima.
    break_time: f32,
    waves: []const Wave,
};

/// Ondas de exemplo para os testes.
pub const example: Waves = @import("example_waves.zon");

pub fn parse(arena: std.mem.Allocator, text: [:0]const u8, diag: *std.zon.parse.Diagnostics) !Waves {
    return std.zon.parse.fromSlice(Waves, .{ .gpa = arena, .arena = arena, .source = text, .diagnostics = diag });
}

/// A onda de número `index` (0 = a primeira); depois da última, a última.
pub fn at(w: Waves, index: u32) Wave {
    const last = w.waves.len - 1;
    return w.waves[@min(index, last)];
}

/// Primeiro problema encontrado nas ondas, ou null se estão boas.
pub fn validate(w: Waves) ?[]const u8 {
    if (w.waves.len == 0) return "waves precisa de pelo menos uma onda";
    if (w.break_time < 0) return "break_time não pode ser negativo";
    for (w.waves) |wave| {
        if (wave.enemies == 0) return "toda onda precisa de pelo menos um inimigo";
        if (wave.interval <= 0) return "interval de toda onda precisa ser maior que 0";
    }
    return null;
}

test "at: devolve a onda do índice, e a última depois do fim" {
    try std.testing.expectEqual(2, at(example, 0).enemies);
    try std.testing.expectEqual(3, at(example, 1).enemies);
    try std.testing.expectEqual(3, at(example, 2).enemies);
    try std.testing.expectEqual(3, at(example, 99).enemies);
}

test "validate: aceita o exemplo" {
    try std.testing.expectEqual(null, validate(example));
}

test "validate: recusa lista vazia, onda sem inimigo, intervalo 0 e pausa negativa" {
    try std.testing.expect(validate(.{ .break_time = 1, .waves = &.{} }) != null);
    try std.testing.expect(validate(.{ .break_time = 1, .waves = &.{.{ .enemies = 0, .interval = 1 }} }) != null);
    try std.testing.expect(validate(.{ .break_time = 1, .waves = &.{.{ .enemies = 1, .interval = 0 }} }) != null);
    try std.testing.expect(validate(.{ .break_time = -1, .waves = &.{.{ .enemies = 1, .interval = 1 }} }) != null);
    try std.testing.expectEqual(null, validate(.{ .break_time = 0, .waves = &.{.{ .enemies = 1, .interval = 1 }} }));
}

test "parse: lê o ZON das ondas" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: std.zon.parse.Diagnostics = undefined;
    const w = try parse(arena.allocator(), ".{ .break_time = 1.5, .waves = .{ .{ .enemies = 4, .interval = 0.5 } } }", &diag);
    try std.testing.expectEqual(1.5, w.break_time);
    try std.testing.expectEqual(4, w.waves[0].enemies);
}
