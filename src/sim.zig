//! Um passo de simulação: chama os sistemas em ordem. Não é um sistema; é a
//! orquestração, aqui na lógica para os testes rodarem sem janela.
const std = @import("std");
const World = @import("world.zig").World;
const mover = @import("systems/mover.zig");
const seguir = @import("systems/seguir.zig");
const spawner = @import("systems/spawner.zig");
const perseguir = @import("systems/perseguir.zig");
const mirar = @import("systems/mirar.zig");
const atacar = @import("systems/atacar.zig");
const magia = @import("systems/magia.zig");
const projeteis = @import("systems/projeteis.zig");
const contato = @import("systems/contato.zig");
const aplicar_dano = @import("systems/aplicar_dano.zig");
const limpar_mortos = @import("systems/limpar_mortos.zig");
const ondas = @import("systems/ondas.zig");

pub const Input = struct {
    /// -1, 0 ou 1.
    turn: f32 = 0,
};

/// Depois do passo, `w.events` tem os eventos dele (para o overlay de debug).
pub fn step(w: *World, gpa: std.mem.Allocator, input: Input, dt: f32) !void {
    w.events.clearRetainingCapacity();
    // Fim de jogo: o mundo congela (a tela mostra a onda alcançada).
    if (w.queue_health.isDead()) return;
    try mover.update(w, gpa, input.turn, dt);
    seguir.update(w);
    try spawner.update(w, gpa, dt);
    perseguir.update(w, dt);
    try mirar.update(w, gpa);
    try atacar.update(w, gpa, dt);
    try magia.update(w, gpa, dt);
    try projeteis.update(w, gpa, dt);
    try contato.update(w, gpa, dt);
    try aplicar_dano.update(w, gpa);
    limpar_mortos.update(w);
    try ondas.update(w, gpa);
}

const config_example = @import("config.zig").example;

test "determinismo: mesma seed e mesma entrada, mesmo estado; seeds diferentes, partidas diferentes" {
    // O helper fica dentro do teste: fora dele, a mutação e os números mágicos o contariam como produção.
    const Play = struct {
        hash: u64 = 0,
        spawned: u32 = 0,
        shots: u32 = 0,
        deaths: u32 = 0,
        waves: u32 = 0,

        /// Joga `ticks` passos com uma entrada que varia, como um jogador faria.
        fn run(gpa: std.mem.Allocator, seed: u64, ticks: u32) !@This() {
            var cfg = config_example();
            cfg.seed = seed;
            var w: World = try .init(gpa, cfg);
            defer w.deinit(gpa);
            const dt = 1.0 / @as(f32, @floatFromInt(cfg.ticks_per_second));
            const turns = [_]f32{ 0, 1, -1 };
            var stats: @This() = .{};
            for (0..ticks) |t| {
                const enemies_before = w.enemies.count;
                const shots_before = w.projectiles.count;
                try step(&w, gpa, .{ .turn = turns[(t / 90) % turns.len] }, dt);
                for (w.events.items) |e| {
                    if (e == .died) stats.deaths += 1;
                }
                if (w.enemies.count > enemies_before) stats.spawned += 1;
                if (w.projectiles.count > shots_before) stats.shots += 1;
            }
            stats.hash = w.hash();
            stats.waves = w.wave;
            return stats;
        }
    };
    const gpa = std.testing.allocator;
    const a = try Play.run(gpa, 7, 1200); // 20 s de jogo
    const b = try Play.run(gpa, 7, 1200);
    // Garante que o teste não passa de graça: houve jogo de verdade, com troca de onda.
    try std.testing.expect(a.spawned > 0 and a.shots > 0 and a.deaths > 0 and a.waves > 0);
    try std.testing.expectEqual(a.hash, b.hash);

    const c = try Play.run(gpa, 8, 1200);
    try std.testing.expect(a.hash != c.hash);
}

test "step: os eventos são só os do passo atual" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example());
    defer w.deinit(gpa);
    try w.events.append(gpa, .{ .damage = .{ .target = .queue, .amount = 1 } });
    try step(&w, gpa, .{}, 0);
    try std.testing.expectEqual(0, w.events.items.len);
}

test "step: com a vida da fila em 0 (fim de jogo), nada mais muda" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example());
    defer w.deinit(gpa);
    w.queue_health.damage(w.queue_health.max);
    const before = w.hash();
    try step(&w, gpa, .{ .turn = 1 }, 0.5);
    try std.testing.expectEqual(before, w.hash());
}
