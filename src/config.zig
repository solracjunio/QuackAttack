//! Formato do `data/game.zon`: todos os números de balanceamento do jogo.
const std = @import("std");
const vec = @import("vec.zig");
const classes_mod = @import("classes.zig");
const Class = classes_mod.Class;
const Vec2 = vec.Vec2;

pub const Config = struct {
    /// Mesma seed, mesma partida (pilar Depurável).
    seed: u64,
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
        /// Classe de cada patinho no começo, da frente para trás (nomes de `classes`).
        start_classes: []const []const u8,
        /// Distância entre patinhos, medida ao longo do caminho da líder.
        spacing: f32,
        radius: f32,
        /// Vida da fila inteira (uma só para todos).
        life: u32,
        /// Segundos sem levar dano de contato depois de um contato.
        invulnerable_time: f32,
    },
    enemy: struct {
        radius: f32,
        speed: f32,
        life: u32,
        /// Dano na fila quando encosta nela.
        contact_damage: u32,
    },
    spawner: struct {
        /// Segundos entre um inimigo e o próximo.
        interval: f32,
    },
    /// Vem de `data/classes.zon` (outro arquivo): o `main` preenche depois de ler.
    classes: []const Class = &.{},
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
        .{ c.queue.life > 0, "queue.life precisa ser maior que 0" },
        .{ c.queue.invulnerable_time >= 0, "queue.invulnerable_time não pode ser negativo" },
        .{ c.enemy.radius > 0, "enemy.radius precisa ser maior que 0" },
        .{ c.enemy.speed > 0, "enemy.speed precisa ser maior que 0" },
        .{ c.enemy.life > 0, "enemy.life precisa ser maior que 0" },
        .{ c.enemy.contact_damage > 0, "enemy.contact_damage precisa ser maior que 0" },
        .{ c.spawner.interval > 0, "spawner.interval precisa ser maior que 0" },
    };
    for (checks) |check| {
        if (!check[0]) return check[1];
    }
    if (classes_mod.validate(c.classes)) |problem| return problem;
    return startClassesProblem(c);
}

fn startClassesProblem(c: Config) ?[]const u8 {
    if (c.queue.start_classes.len == 0) return "queue.start_classes precisa de pelo menos um patinho";
    for (c.queue.start_classes) |name| {
        if (classes_mod.find(c.classes, name) == null) return "queue.start_classes cita uma classe que não existe em classes.zon";
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
    var c = parse(arena.allocator(), sample, &diag) catch unreachable;
    // Os nomes do texto morrem com o arena: o exemplo usa a lista fixa abaixo.
    c.queue.start_classes = &example_start_classes;
    c.classes = classes_mod.example;
    return c;
}

const example_start_classes = [_][]const u8{ "arqueiro", "arqueiro", "mago" };

const sample =
    \\.{
    \\    .seed = 42,
    \\    .ticks_per_second = 60,
    \\    .world = .{ .width = 800, .height = 600 },
    \\    .leader = .{ .start = .{ 400, 300 }, .start_heading = .{ 1, 0 }, .speed = 150, .turn_speed = 3, .radius = 12 },
    \\    .queue = .{ .start_classes = .{ "arqueiro", "arqueiro", "mago" }, .spacing = 26, .radius = 10, .life = 10, .invulnerable_time = 1 },
    \\    .enemy = .{ .radius = 10, .speed = 60, .life = 3, .contact_damage = 2 },
    \\    .spawner = .{ .interval = 2 },
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
    try std.testing.expectEqual(3, c.queue.start_classes.len);
    try std.testing.expectEqualStrings("mago", c.queue.start_classes[2]);
    try std.testing.expectEqual(42, c.seed);
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
    c = base;
    c.queue.life = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.queue.invulnerable_time = -1;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.enemy.radius = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.enemy.speed = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.enemy.life = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.enemy.contact_damage = 0;
    try std.testing.expect(validate(c) != null);
    c = base;
    c.spawner.interval = 0;
    try std.testing.expect(validate(c) != null);
}

test "validate: invulnerable_time 0 é válido (sem invulnerabilidade)" {
    var c = example();
    c.queue.invulnerable_time = 0;
    try std.testing.expectEqual(null, validate(c));
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

test "validate: classes inválidas ou classe inicial que não existe" {
    var c = example();
    c.classes = &.{};
    try std.testing.expect(validate(c) != null);

    c = example();
    c.queue.start_classes = &.{ "arqueiro", "bardo" };
    try std.testing.expect(validate(c) != null);

    c = example();
    c.queue.start_classes = &.{};
    try std.testing.expect(validate(c) != null);
}
