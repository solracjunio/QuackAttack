//! Formato do `data/game.zon`: todos os números de balanceamento do jogo.
const std = @import("std");
const vec = @import("vec.zig");
const Vec2 = vec.Vec2;

pub const Config = struct {
    /// Passos de simulação por segundo (passo fixo).
    ticks_per_second: u32,
    /// Área de jogo; a líder é refletida nas bordas.
    world: struct { width: f32, height: f32 },
    leader: struct {
        start: Vec2,
        /// Direção inicial (será normalizada).
        start_heading: Vec2,
        /// Unidades por segundo.
        speed: f32,
        /// Radianos por segundo com a tecla de giro apertada.
        turn_speed: f32,
        radius: f32,
    },
    queue: struct {
        start_ducks: u32,
        /// Distância entre patinhos, medida ao longo do caminho da líder.
        spacing: f32,
        radius: f32,
    },
};

pub const ParseError = error{ OutOfMemory, ParseZon };

/// Lê a configuração do texto ZON. Em erro, `diag` diz o que está errado.
pub fn parse(arena: std.mem.Allocator, text: [:0]const u8, diag: *std.zon.parse.Diagnostics) ParseError!Config {
    return std.zon.parse.fromSlice(Config, .{ .gpa = arena, .arena = arena, .source = text, .diagnostics = diag });
}

/// Primeiro problema encontrado na configuração, ou null se ela está boa.
pub fn validate(c: Config) ?[]const u8 {
    const l = c.leader;
    const checks = [_]struct { bool, []const u8 }{
        .{ c.ticks_per_second > 0, "ticks_per_second precisa ser maior que 0" },
        .{ l.speed > 0, "leader.speed precisa ser maior que 0" },
        .{ l.turn_speed >= 0, "leader.turn_speed não pode ser negativo" },
        .{ l.radius > 0, "leader.radius precisa ser maior que 0" },
        .{ vec.length(l.start_heading) > 0, "leader.start_heading não pode ser (0, 0)" },
        // Também garante um mundo com largura e altura maiores que 0, já que o raio é > 0.
        .{ insideWorld(c, l.start, l.radius), "leader.start precisa ficar dentro do mundo, contando o raio" },
        .{ c.queue.spacing > 0, "queue.spacing precisa ser maior que 0" },
        .{ c.queue.radius > 0, "queue.radius precisa ser maior que 0" },
    };
    for (checks) |check| {
        if (!check[0]) return check[1];
    }
    return null;
}

fn insideWorld(c: Config, p: Vec2, radius: f32) bool {
    const max: Vec2 = .{ c.world.width - radius, c.world.height - radius };
    return @reduce(.And, p >= @as(Vec2, @splat(radius))) and @reduce(.And, p <= max);
}

/// Configuração de exemplo para os testes (o mesmo texto do teste de `parse`).
/// Só pode ser chamada em testes: usa o `std.testing.allocator`.
pub fn example() Config {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: std.zon.parse.Diagnostics = undefined;
    return parse(arena.allocator(), sample, &diag) catch unreachable;
}

const sample =
    \\.{
    \\    .ticks_per_second = 60,
    \\    .world = .{ .width = 800, .height = 600 },
    \\    .leader = .{ .start = .{ 400, 300 }, .start_heading = .{ 1, 0 }, .speed = 150, .turn_speed = 3, .radius = 12 },
    \\    .queue = .{ .start_ducks = 3, .spacing = 26, .radius = 10 },
    \\}
;

test "parse: lê o ZON da configuração" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: std.zon.parse.Diagnostics = undefined;
    const c = try parse(arena.allocator(), sample, &diag);
    try std.testing.expectEqual(60, c.ticks_per_second);
    try std.testing.expectEqual(800, c.world.width);
    try std.testing.expectEqual(300, c.leader.start[1]);
    try std.testing.expectEqual(3, c.queue.start_ducks);
}

test "parse: campo faltando é erro" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diag: std.zon.parse.Diagnostics = undefined;
    try std.testing.expectError(error.ParseZon, parse(arena.allocator(), ".{ .ticks_per_second = 60 }", &diag));
}

test "validate: aceita o exemplo" {
    try std.testing.expectEqual(null, validate(example()));
}

test "validate: recusa valores que quebram o jogo" {
    const base = example();
    var c = base;
    c.ticks_per_second = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.world.height = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.leader.speed = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.leader.turn_speed = -1;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.leader.radius = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.leader.start_heading = .{ 0, 0 };
    try std.testing.expect(validate(c) != null);
    c = base;
    c.queue.spacing = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.queue.radius = 0;
    try std.testing.expect(validate(c) != null);
}

test "validate: turn_speed 0 é válido (a líder só não vira)" {
    var c = example();
    c.leader.turn_speed = 0;
    try std.testing.expectEqual(null, validate(c));
}

test "validate: a líder precisa começar dentro do mundo, com o raio" {
    var c = example(); // mundo 800x600, raio 12
    c.leader.start = .{ 12, 588 };
    try std.testing.expectEqual(null, validate(c));
    c.leader.start = .{ 11, 300 };
    try std.testing.expect(validate(c) != null);
    c.leader.start = .{ 400, 589 };
    try std.testing.expect(validate(c) != null);
    c.leader.start = .{ 789, 300 };
    try std.testing.expect(validate(c) != null);
    c.leader.start = .{ 400, 11 };
    try std.testing.expect(validate(c) != null);
}
