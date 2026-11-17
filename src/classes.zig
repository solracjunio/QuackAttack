//! Classes de patinho, lidas de `data/classes.zon`. Uma classe nova que usa um
//! ataque que já existe é só uma entrada no arquivo de dados.
const std = @import("std");

/// Acessório na cabeça (`docs/guia-visual.md`, "Patos").
pub const Hat = enum { hood, pointed };
/// Cor de destaque da classe (vira uma cor da paleta na interface).
pub const Accent = enum { green, blue };

pub const Look = struct { hat: Hat, accent: Accent };

/// Comportamento de ataque. Um tipo novo aqui precisa de um sistema que o use.
pub const Attack = union(enum) {
    /// Atira no alvo que estiver mirando.
    projectile: struct { range: f32, cooldown: f32, damage: u32, speed: f32, radius: f32 },
    /// Dano em todos os inimigos dentro do raio, em volta de si.
    area: struct { radius: f32, cooldown: f32, damage: u32 },
};

pub const Class = struct {
    name: []const u8,
    look: Look,
    attack: Attack,
};

/// Classes de exemplo para os testes.
pub const example: []const Class = @import("example_classes.zon");

pub fn parse(arena: std.mem.Allocator, text: [:0]const u8, diag: *std.zon.parse.Diagnostics) ![]const Class {
    return std.zon.parse.fromSlice([]const Class, .{ .gpa = arena, .arena = arena, .source = text, .diagnostics = diag });
}

/// Índice da classe com esse nome.
pub fn find(classes: []const Class, name: []const u8) ?u32 {
    for (classes, 0..) |c, i| {
        if (std.mem.eql(u8, c.name, name)) return @intCast(i);
    }
    return null;
}

/// Primeiro problema encontrado nas classes, ou null se estão boas.
pub fn validate(classes: []const Class) ?[]const u8 {
    if (classes.len == 0) return "precisa de pelo menos uma classe";
    for (classes, 0..) |c, i| {
        if (find(classes, c.name) != @as(u32, @intCast(i))) return "nomes de classe repetidos";
        if (attackProblem(c.attack)) |problem| return problem;
    }
    return null;
}

const Check = struct { bool, []const u8 };

fn attackProblem(attack: Attack) ?[]const u8 {
    const checks: []const Check = switch (attack) {
        .projectile => |a| &.{
            .{ a.range > 0, "attack.projectile.range precisa ser maior que 0" },
            .{ a.cooldown > 0, "attack.projectile.cooldown precisa ser maior que 0" },
            .{ a.damage > 0, "attack.projectile.damage precisa ser maior que 0" },
            .{ a.speed > 0, "attack.projectile.speed precisa ser maior que 0" },
            .{ a.radius > 0, "attack.projectile.radius precisa ser maior que 0" },
        },
        .area => |a| &.{
            .{ a.radius > 0, "attack.area.radius precisa ser maior que 0" },
            .{ a.cooldown > 0, "attack.area.cooldown precisa ser maior que 0" },
            .{ a.damage > 0, "attack.area.damage precisa ser maior que 0" },
        },
    };
    for (checks) |check| {
        if (!check[0]) return check[1];
    }
    return null;
}

test "parse: lê classes com ataques diferentes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: std.zon.parse.Diagnostics = undefined;
    const cs = try parse(arena.allocator(),
        \\.{ .{ .name = "mago", .look = .{ .hat = .pointed, .accent = .blue },
        \\      .attack = .{ .area = .{ .radius = 50, .cooldown = 2, .damage = 3 } } } }
    , &diag);
    try std.testing.expectEqual(1, cs.len);
    try std.testing.expectEqualStrings("mago", cs[0].name);
    try std.testing.expectEqual(50, cs[0].attack.area.radius);
}

test "find: acha pelo nome" {
    try std.testing.expectEqual(1, find(example, "mago"));
    try std.testing.expectEqual(0, find(example, "arqueiro"));
    try std.testing.expectEqual(null, find(example, "bardo"));
}

test "validate: aceita o exemplo" {
    try std.testing.expectEqual(null, validate(example));
}

test "validate: recusa lista vazia e nomes repetidos" {
    try std.testing.expect(validate(&.{}) != null);
    const twice = [_]Class{ example[0], example[0] };
    try std.testing.expect(validate(&twice) != null);
}

test "validate: recusa ataques com valores que quebram o jogo" {
    const base_p = example[0].attack.projectile;
    const base_a = example[1].attack.area;
    const Case = struct { []const u8, Attack };
    const cases = [_]Case{
        .{ "range", .{ .projectile = blk: {
            var a = base_p;
            a.range = 0;
            break :blk a;
        } } },
        .{ "cooldown", .{ .projectile = blk: {
            var a = base_p;
            a.cooldown = 0;
            break :blk a;
        } } },
        .{ "damage", .{ .projectile = blk: {
            var a = base_p;
            a.damage = 0;
            break :blk a;
        } } },
        .{ "speed", .{ .projectile = blk: {
            var a = base_p;
            a.speed = 0;
            break :blk a;
        } } },
        .{ "radius", .{ .projectile = blk: {
            var a = base_p;
            a.radius = 0;
            break :blk a;
        } } },
        .{ "area radius", .{ .area = blk: {
            var a = base_a;
            a.radius = 0;
            break :blk a;
        } } },
        .{ "area cooldown", .{ .area = blk: {
            var a = base_a;
            a.cooldown = 0;
            break :blk a;
        } } },
        .{ "area damage", .{ .area = blk: {
            var a = base_a;
            a.damage = 0;
            break :blk a;
        } } },
    };
    for (cases) |c| {
        var one = [_]Class{example[0]};
        one[0].attack = c[1];
        if (validate(&one) == null) {
            std.debug.print("deveria recusar: {s}\n", .{c[0]});
            return error.TestExpectedProblem;
        }
    }
}
