//! Histórico de posições da líder. Os patinhos ficam em pontos desse
//! caminho, a uma distância fixa um do outro, medida ao longo dele.
const std = @import("std");
const expectVec = @import("testing.zig").expectVec;
const vec = @import("vec.zig");
const Vec2 = vec.Vec2;

pub const Trail = struct {
    /// Do mais antigo ao mais novo. Somente leitura fora deste arquivo.
    points: std.ArrayList(Vec2) = .empty,

    pub fn deinit(self: *Trail, gpa: std.mem.Allocator) void {
        self.points.deinit(gpa);
    }

    pub fn push(self: *Trail, gpa: std.mem.Allocator, p: Vec2) !void {
        try self.points.append(gpa, p);
    }

    /// Ponto a `distance` atrás do mais novo, medido ao longo do caminho.
    /// Se o caminho for mais curto, devolve o ponto mais antigo.
    pub fn pointAt(self: Trail, distance: f32) Vec2 {
        const pts = self.points.items;
        var left = distance;
        var i = pts.len - 1;
        while (i > 0) : (i -= 1) {
            const segment = pts[i - 1] - pts[i];
            const len = vec.length(segment);
            if (len == 0) continue;
            // mutation: disable — com left == len, `<` e `<=` dão o mesmo ponto (fim deste segmento = começo do próximo)
            const in_segment = left <= len;
            if (in_segment) return pts[i] + vec.scale(segment, left / len);
            left -= len;
        }
        return pts[0];
    }

    /// Descarta os pontos que ficam além de `keep` de distância do mais novo.
    pub fn prune(self: *Trail, keep: f32) void {
        const pts = self.points.items;
        var walked: f32 = 0;
        var i = pts.len - 1;
        while (i > 0 and walked < keep) : (i -= 1) {
            walked += vec.length(pts[i - 1] - pts[i]);
        }
        // pts[i] é o mais antigo necessário: tudo antes dele sai.
        self.points.replaceRangeAssumeCapacity(0, i, &.{});
    }
};

fn trailFrom(gpa: std.mem.Allocator, points: []const Vec2) !Trail {
    var t: Trail = .{};
    for (points) |p| try t.push(gpa, p);
    return t;
}

test "pointAt: mede a distância ao longo do caminho, dobrando a esquina" {
    const gpa = std.testing.allocator;
    var t = try trailFrom(gpa, &.{ .{ 0, 0 }, .{ 10, 0 }, .{ 10, 10 } }); // em L
    defer t.deinit(gpa);
    try expectVec(.{ 10, 10 }, t.pointAt(0));
    try expectVec(.{ 10, 5 }, t.pointAt(5));
    try expectVec(.{ 10, 0 }, t.pointAt(10));
    try expectVec(.{ 5, 0 }, t.pointAt(15));
}

test "pointAt: além do fim do caminho, devolve o ponto mais antigo" {
    const gpa = std.testing.allocator;
    var t = try trailFrom(gpa, &.{ .{ 0, 0 }, .{ 10, 0 }, .{ 10, 10 } }); // em L
    defer t.deinit(gpa);
    try expectVec(.{ 0, 0 }, t.pointAt(100));
}

test "pointAt: pontos repetidos (segmento de comprimento 0) não geram NaN" {
    const gpa = std.testing.allocator;
    var t: Trail = .{};
    defer t.deinit(gpa);
    for ([_]Vec2{ .{ 0, 0 }, .{ 4, 0 }, .{ 4, 0 } }) |p| try t.push(gpa, p);
    try expectVec(.{ 4, 0 }, t.pointAt(0));
    try expectVec(.{ 1, 0 }, t.pointAt(3));
}

test "prune: guarda só os pontos necessários para medir até `keep`" {
    const gpa = std.testing.allocator;
    var t = try trailFrom(gpa, &.{ .{ 0, 0 }, .{ 10, 0 }, .{ 10, 10 } }); // em L
    defer t.deinit(gpa);
    t.prune(5);
    try std.testing.expectEqual(2, t.points.items.len);
    try expectVec(.{ 10, 5 }, t.pointAt(5));
}

test "prune: não remove o ponto que fecha o segmento onde `keep` cai" {
    const gpa = std.testing.allocator;
    var t = try trailFrom(gpa, &.{ .{ 0, 0 }, .{ 10, 0 }, .{ 10, 10 } }); // em L
    defer t.deinit(gpa);
    t.prune(10);
    try std.testing.expectEqual(2, t.points.items.len);

    var u = try trailFrom(gpa, &.{ .{ 0, 0 }, .{ 10, 0 }, .{ 10, 10 } }); // em L
    defer u.deinit(gpa);
    u.prune(10.5);
    try std.testing.expectEqual(3, u.points.items.len);
}

test "prune: `keep` maior que o caminho inteiro guarda tudo" {
    const gpa = std.testing.allocator;
    var t = try trailFrom(gpa, &.{ .{ 0, 0 }, .{ 10, 0 }, .{ 10, 10 } });
    defer t.deinit(gpa);
    t.prune(1000);
    try std.testing.expectEqual(3, t.points.items.len);
}
