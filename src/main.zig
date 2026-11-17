//! Loop do jogo: só orquestra. A lógica fica no módulo `game`.
const std = @import("std");
const rl = @import("raylib");
const game = @import("game");
const World = game.world.World;
const Event = game.events.Event;
const debug = @import("ui/debug.zig");
const Renderer = @import("ui/render.zig").Renderer;

const data_path = "data/game.zon";

/// Passo de frame mais longo que a simulação aceita, em segundos. Evita uma
/// avalanche de passos depois de uma pausa (janela arrastada, depurador).
const max_frame_seconds = 0.25;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const config = try loadConfig(init);

    var world: World = try .init(gpa, config);
    defer world.deinit(gpa);
    // Eventos de todos os passos do frame, para o overlay de debug.
    var frame_events: std.ArrayList(Event) = .empty;
    defer frame_events.deinit(gpa);
    var show_debug = false;

    const width: i32 = @intFromFloat(config.world.width);
    const height: i32 = @intFromFloat(config.world.height);
    rl.initWindow(width, height, "QuackAttack");
    defer rl.closeWindow();
    const renderer: Renderer = try .init(width, height);
    defer renderer.deinit();

    const step = 1.0 / @as(f32, @floatFromInt(config.ticks_per_second));
    var pending: f32 = 0;
    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(.f1)) show_debug = !show_debug;
        frame_events.clearRetainingCapacity();
        pending += @min(rl.getFrameTime(), max_frame_seconds);
        while (pending >= step) : (pending -= step) {
            try game.sim.step(&world, gpa, .{ .turn = readTurn() }, step);
            try frame_events.appendSlice(gpa, world.events.items);
        }

        renderer.render(world);
        rl.beginDrawing();
        defer rl.endDrawing();
        renderer.present();
        if (show_debug) debug.draw(world, frame_events.items);
    }
}

/// Lê e valida `data/game.zon`. Em erro, explica no terminal e encerra.
fn loadConfig(init: std.process.Init) !game.config.Config {
    const arena = init.arena.allocator();
    const text = try std.Io.Dir.cwd().readFileAllocOptions(init.io, data_path, arena, .unlimited, .of(u8), 0);
    var diag: std.zon.parse.Diagnostics = undefined;
    const config = game.config.parse(arena, text, &diag) catch |err| {
        diag.log(data_path);
        return err;
    };
    if (game.config.validate(config)) |problem| {
        std.log.err("{s}: {s}", .{ data_path, problem });
        return error.InvalidData;
    }
    return config;
}

/// -1, 0 ou 1. Com y para baixo na tela, girar positivo é girar no sentido horário.
fn readTurn() f32 {
    var turn: f32 = 0;
    if (rl.isKeyDown(.right) or rl.isKeyDown(.d)) turn += 1;
    if (rl.isKeyDown(.left) or rl.isKeyDown(.a)) turn -= 1;
    return turn;
}
