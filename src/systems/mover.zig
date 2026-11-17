//! Sistema `mover`: anda com a líder, gira pela entrada do jogador e reflete
//! nas bordas. Grava cada posição no caminho que a fila segue.
const std = @import("std");
const expectVec = @import("../testing.zig").expectVec;
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const world = @import("../world.zig");
const World = world.World;
const Leader = world.Leader;

/// `turn`: -1, 0 ou 1 (sentido do giro). `dt`: segundos do passo.
pub fn update(w: *World, gpa: std.mem.Allocator, turn: f32, dt: f32) !void {
    const cfg = w.config.leader;
    const l = &w.leader;
    // Normalizar a cada passo evita que o vetor encolha ou cresça por arredondamento.
    l.heading = vec.normalize(vec.rotate(l.heading, turn * cfg.turn_speed * dt));
    l.pos += vec.scale(l.heading, cfg.speed * dt);
    reflectAxis(l, 0, w.config.world.width - cfg.radius, cfg.radius);
    reflectAxis(l, 1, w.config.world.height - cfg.radius, cfg.radius);
    try w.trail.push(gpa, l.pos);
}

/// Num eixo: se a líder passou de `min` ou `max` indo para fora, espelha a
/// posição de volta para dentro e inverte o sentido.
fn reflectAxis(l: *Leader, comptime axis: comptime_int, max: f32, min: f32) void {
    const pos = l.pos[axis];
    const dir = l.heading[axis];
    if (pos < min and dir < 0) {
        l.pos[axis] = min + (min - pos);
        l.heading[axis] = -dir;
    } else if (pos > max and dir > 0) {
        l.pos[axis] = max - (pos - max);
        l.heading[axis] = -dir;
    }
}

const config_example = @import("../config.zig").example;

test "update: sem giro, anda `speed * dt` para a frente e grava no caminho" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // (400, 300), +x, speed 150
    defer w.deinit(gpa);
    try update(&w, gpa, 0, 0.1);
    try expectVec(.{ 415, 300 }, w.leader.pos);
    const pts = w.trail.points.items;
    try expectVec(.{ 415, 300 }, pts[pts.len - 1]);
}

test "update: girar muda a direção em `turn * turn_speed * dt` radianos" {
    const gpa = std.testing.allocator;
    var cfg = config_example();
    cfg.leader.turn_speed = std.math.pi; // meia volta por segundo
    var w: World = try .init(gpa, cfg);
    defer w.deinit(gpa);
    try update(&w, gpa, 1, 0.5); // um quarto de volta
    try expectVec(.{ 0, 1 }, w.leader.heading);
    try update(&w, gpa, -1, 0.5); // e de volta
    try expectVec(.{ 1, 0 }, w.leader.heading);
}

/// Líder do exemplo (raio 12, speed 150, mundo 800x600) em `pos`, olhando para `heading`.
fn worldAt(gpa: std.mem.Allocator, pos: Vec2, heading: Vec2) !World {
    var w: World = try .init(gpa, config_example());
    w.leader = .{ .pos = pos, .heading = heading };
    return w;
}

test "update: reflete nas quatro bordas, considerando o raio" {
    const gpa = std.testing.allocator;
    const cases = [_]struct { pos: Vec2, heading: Vec2, want_pos: Vec2, want_heading: Vec2 }{
        // Anda 15: passa 13 do limite (o raio, 12) e volta 13 para dentro.
        .{ .pos = .{ 14, 300 }, .heading = .{ -1, 0 }, .want_pos = .{ 25, 300 }, .want_heading = .{ 1, 0 } },
        .{ .pos = .{ 786, 300 }, .heading = .{ 1, 0 }, .want_pos = .{ 775, 300 }, .want_heading = .{ -1, 0 } },
        .{ .pos = .{ 400, 14 }, .heading = .{ 0, -1 }, .want_pos = .{ 400, 25 }, .want_heading = .{ 0, 1 } },
        .{ .pos = .{ 400, 586 }, .heading = .{ 0, 1 }, .want_pos = .{ 400, 575 }, .want_heading = .{ 0, -1 } },
    };
    for (cases) |c| {
        var w = try worldAt(gpa, c.pos, c.heading);
        defer w.deinit(gpa);
        try update(&w, gpa, 0, 0.1);
        try expectVec(c.want_pos, w.leader.pos);
        try expectVec(c.want_heading, w.leader.heading);
    }
}

test "update: no canto, reflete nos dois eixos" {
    const gpa = std.testing.allocator;
    const d = vec.normalize(.{ -1, -1 });
    var w = try worldAt(gpa, .{ 12.5, 12.5 }, d);
    defer w.deinit(gpa);
    try update(&w, gpa, 0, 0.1);
    try expectVec(-d, w.leader.heading);
    try std.testing.expect(w.leader.pos[0] >= 12 and w.leader.pos[1] >= 12);
}

test "update: encostada exatamente na borda ainda não reflete" {
    const gpa = std.testing.allocator;
    var w = try worldAt(gpa, .{ 12, 588 }, vec.normalize(.{ -1, 1 }));
    defer w.deinit(gpa);
    try update(&w, gpa, 0, 0);
    try expectVec(vec.normalize(.{ -1, 1 }), w.leader.heading);
}

test "update: fora da borda mas já voltando, não reflete de novo" {
    const gpa = std.testing.allocator;
    var w = try worldAt(gpa, .{ 5, 595 }, vec.normalize(.{ 1, -1 }));
    defer w.deinit(gpa);
    try update(&w, gpa, 0, 0);
    try expectVec(.{ 5, 595 }, w.leader.pos);
    try expectVec(vec.normalize(.{ 1, -1 }), w.leader.heading);
}

test "update: fora da borda andando paralelo a ela, não é empurrada" {
    const gpa = std.testing.allocator;
    const cases = [_]struct { pos: Vec2, heading: Vec2 }{
        .{ .pos = .{ 5, 300 }, .heading = .{ 0, 1 } },
        .{ .pos = .{ 795, 300 }, .heading = .{ 0, -1 } },
        .{ .pos = .{ 400, 5 }, .heading = .{ 1, 0 } },
        .{ .pos = .{ 400, 595 }, .heading = .{ -1, 0 } },
    };
    for (cases) |c| {
        var w = try worldAt(gpa, c.pos, c.heading);
        defer w.deinit(gpa);
        try update(&w, gpa, 0, 0);
        try expectVec(c.pos, w.leader.pos);
    }
}
