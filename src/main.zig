//! Loop do jogo: só orquestra. A lógica fica no módulo `game`.
const std = @import("std");
const rl = @import("raylib");
const game = @import("game");
const World = game.world.World;
const Vec2 = game.vec.Vec2;

const data_path = "data/game.zon";

/// Passo de frame mais longo que a simulação aceita, em segundos. Evita uma
/// avalanche de passos depois de uma pausa (janela arrastada, depurador).
const max_frame_seconds = 0.25;

const leader_color: rl.Color = .orange;
const duck_color: rl.Color = .yellow;
const background: rl.Color = .dark_green;
const eye_offset = 0.5; // fração do raio
const eye_radius = 3;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const config = try loadConfig(init);

    var world: World = try .init(gpa, config);
    defer world.deinit(gpa);

    rl.initWindow(@intFromFloat(config.world.width), @intFromFloat(config.world.height), "QuackAttack");
    defer rl.closeWindow();

    const step = 1.0 / @as(f32, @floatFromInt(config.ticks_per_second));
    var pending: f32 = 0;
    while (!rl.windowShouldClose()) {
        pending += @min(rl.getFrameTime(), max_frame_seconds);
        while (pending >= step) : (pending -= step) {
            try game.mover.update(&world, gpa, readTurn(), step);
            game.seguir.update(&world);
        }

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(background);
        draw(world);
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

fn draw(world: World) void {
    const ducks = world.ducks.items(.pos);
    // Do fim da fila para a frente: quem vem antes fica por cima.
    var i = ducks.len;
    while (i > 0) {
        i -= 1;
        rl.drawCircleV(toRl(ducks[i]), world.config.queue.radius, duck_color);
    }
    const l = world.leader;
    const radius = world.config.leader.radius;
    rl.drawCircleV(toRl(l.pos), radius, leader_color);
    // Um "olho" na frente, para ver a direção.
    rl.drawCircleV(toRl(l.pos + game.vec.scale(l.heading, radius * eye_offset)), eye_radius, .black);
}

fn toRl(v: Vec2) rl.Vector2 {
    return .{ .x = v[0], .y = v[1] };
}
