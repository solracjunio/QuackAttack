//! Dados do jogo. Os sistemas (`systems/`) são funções sobre estes dados.
const std = @import("std");
const expectVec = @import("testing.zig").expectVec;
const vec = @import("vec.zig");
const Vec2 = vec.Vec2;
const Config = @import("config.zig").Config;
const Trail = @import("trail.zig").Trail;

pub const Leader = struct {
    pos: Vec2,
    /// Vetor unitário.
    heading: Vec2,
};

pub const Duck = struct {
    pos: Vec2,
};

pub const World = struct {
    config: Config,
    leader: Leader,
    trail: Trail = .{},
    /// Na ordem da fila: o primeiro vem logo atrás da líder.
    ducks: std.MultiArrayList(Duck) = .empty,

    pub fn init(gpa: std.mem.Allocator, config: Config) !World {
        const start = config.leader.start;
        const heading = vec.normalize(config.leader.start_heading);
        var w: World = .{ .config = config, .leader = .{ .pos = start, .heading = heading } };
        errdefer w.deinit(gpa);

        // Caminho reto atrás da líder, longo o bastante para a fila inicial.
        const behind = start - vec.scale(heading, w.duckDistance(config.queue.start_ducks));
        try w.trail.push(gpa, behind);
        try w.trail.push(gpa, start);

        for (0..config.queue.start_ducks) |i| {
            try w.ducks.append(gpa, .{ .pos = w.trail.pointAt(w.duckDistance(i)) });
        }
        return w;
    }

    pub fn deinit(self: *World, gpa: std.mem.Allocator) void {
        self.trail.deinit(gpa);
        self.ducks.deinit(gpa);
    }

    /// Distância ao longo do caminho até o patinho `index` (0 = o primeiro).
    pub fn duckDistance(self: World, index: usize) f32 {
        return @as(f32, @floatFromInt(index + 1)) * self.config.queue.spacing;
    }
};

const config_example = @import("config.zig").example;

test "init: líder no início, olhando para a direção inicial normalizada" {
    var cfg = config_example();
    cfg.leader.start_heading = .{ 0, 2 };
    var w: World = try .init(std.testing.allocator, cfg);
    defer w.deinit(std.testing.allocator);
    try expectVec(cfg.leader.start, w.leader.pos);
    try expectVec(.{ 0, 1 }, w.leader.heading);
}

test "init: patinhos em fila atrás da líder, um espaçamento entre cada" {
    const cfg = config_example(); // líder em (400, 300) olhando para +x, espaçamento 26
    var w: World = try .init(std.testing.allocator, cfg);
    defer w.deinit(std.testing.allocator);
    try std.testing.expectEqual(cfg.queue.start_ducks, w.ducks.len);
    const pos = w.ducks.items(.pos);
    try expectVec(.{ 374, 300 }, pos[0]);
    try expectVec(.{ 348, 300 }, pos[1]);
    try expectVec(.{ 322, 300 }, pos[2]);
}

fn initAndDeinit(gpa: std.mem.Allocator) !void {
    var w: World = try .init(gpa, config_example());
    w.deinit(gpa);
}

test "init: sem memória em qualquer alocação, devolve erro e não vaza" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initAndDeinit, .{});
}
