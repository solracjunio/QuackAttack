//! Sistema `seguir`: põe cada patinho que segue a líder `(Segue, líder)` no
//! caminho dela, a um espaçamento do anterior, e descarta o caminho que nenhum
//! patinho usa mais.
const std = @import("std");
const expectVec = @import("../testing.zig").expectVec;
const vec = @import("../vec.zig");
const Vec2 = vec.Vec2;
const World = @import("../world.zig").World;

pub fn update(w: *World) void {
    const positions = w.ducks.items(.pos);
    var followers = w.relations.query(.segue, .{ .is = .leader });
    while (followers.next()) |r| {
        const i = r.source.duck;
        positions[i] = w.trail.pointAt(w.duckDistance(i));
    }
    // Guarda um espaçamento a mais que o último patinho.
    w.trail.prune(w.duckDistance(w.ducks.len));
}

const config_example = @import("../config.zig").example;

test "update: cada patinho fica um espaçamento atrás do anterior, ao longo do caminho" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example()); // espaçamento 26, 3 patinhos
    defer w.deinit(gpa);
    // A líder subiu 30 a partir de (400, 300): o caminho dobra a esquina.
    w.leader.pos = .{ 400, 270 };
    try w.trail.push(gpa, w.leader.pos);
    update(&w);
    const pos = w.ducks.items(.pos);
    try expectVec(.{ 400, 296 }, pos[0]);
    try expectVec(.{ 378, 300 }, pos[1]);
    try expectVec(.{ 352, 300 }, pos[2]);
}

test "update: o caminho não cresce sem limite" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example());
    defer w.deinit(gpa);
    var p = w.leader.pos;
    for (0..1000) |_| {
        p += .{ 1, 0 };
        try w.trail.push(gpa, p);
        update(&w);
    }
    // Passos de 1; guarda-se até 4 espaçamentos (104): uns 105 pontos, não 1000.
    try std.testing.expect(w.trail.points.items.len < 110);
}

test "update: só move quem tem a relação (Segue, líder)" {
    const gpa = std.testing.allocator;
    var w: World = try .init(gpa, config_example());
    defer w.deinit(gpa);
    w.relations.clear(.segue, .{ .duck = 1 });
    const parked = w.ducks.items(.pos)[1];
    w.leader.pos = .{ 400, 270 };
    try w.trail.push(gpa, w.leader.pos);
    update(&w);
    try expectVec(.{ 400, 296 }, w.ducks.items(.pos)[0]);
    try expectVec(parked, w.ducks.items(.pos)[1]);
}
