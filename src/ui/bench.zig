//! Benchmark (`zig build run -- --bench`): quantas entidades na tela antes de
//! o FPS cair abaixo de 60. Sem ondas e sem fim de jogo; a cada etapa entram
//! mais inimigos, e a etapa mede o tempo médio da simulação e do frame inteiro,
//! com o FPS destravado. Imprime uma tabela no terminal.
const std = @import("std");
const rl = @import("raylib");
const game = @import("game");
const World = game.world.World;
const Renderer = @import("render.zig").Renderer;

const stage_seconds = 2.0;
const enemies_per_stage = 250;
const max_enemies = 20000;
const target_fps = 60.0;

pub fn run(gpa: std.mem.Allocator, base: game.config.Config, renderer: Renderer) !void {
    var config = base;
    // Sem fim de jogo: a fila não morre. Os inimigos também não: continuam
    // levando tiros e feitiços (o custo do combate entra na medida), mas a
    // quantidade na tela só cresce.
    config.queue.life = std.math.maxInt(u32);
    config.enemy.life = std.math.maxInt(u32);
    var world: World = try .init(gpa, config);
    defer world.deinit(gpa);
    // Sem ondas: o benchmark põe os inimigos.
    world.wave_break = std.math.floatMax(f32);

    rl.setTargetFPS(0);
    const step = 1.0 / @as(f32, @floatFromInt(config.ticks_per_second));
    std.debug.print("{s:>9} {s:>8} {s:>9} {s:>10} {s:>6}\n", .{ "inimigos", "flechas", "sim (ms)", "frame (ms)", "FPS" });

    while (!rl.windowShouldClose()) {
        var frames: u32 = 0;
        var sim_total: f64 = 0;
        const stage_start = rl.getTime();
        while (rl.getTime() - stage_start < stage_seconds and !rl.windowShouldClose()) : (frames += 1) {
            const sim_start = rl.getTime();
            try game.sim.step(&world, gpa, .{ .turn = 0.5 }, step);
            sim_total += rl.getTime() - sim_start;
            renderer.render(world);
            rl.beginDrawing();
            renderer.present();
            rl.endDrawing();
        }
        const elapsed = rl.getTime() - stage_start;
        const fps = @as(f64, @floatFromInt(frames)) / elapsed;
        std.debug.print("{d:>9} {d:>8} {d:>9.3} {d:>10.3} {d:>6.0}\n", .{
            world.enemies.count,
            world.projectiles.count,
            sim_total * 1000 / @as(f64, @floatFromInt(frames)),
            elapsed * 1000 / @as(f64, @floatFromInt(frames)),
            fps,
        });
        if (fps < target_fps or world.enemies.count >= max_enemies) break;
        try addEnemies(gpa, &world, enemies_per_stage);
    }
}

/// Inimigos em pontos aleatórios do mundo (gerador do próprio mundo).
fn addEnemies(gpa: std.mem.Allocator, w: *World, n: u32) !void {
    const random = w.rng.random();
    for (0..n) |_| {
        const pos: game.vec.Vec2 = .{ random.float(f32) * w.config.world.width, random.float(f32) * w.config.world.height };
        _ = try w.enemies.add(gpa, .{ .pos = pos, .health = .init(w.config.enemy.life) });
    }
}
