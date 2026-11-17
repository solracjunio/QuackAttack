//! Dados do jogo. Os sistemas (`systems/`) são funções sobre estes dados.
const std = @import("std");
const expectVec = @import("testing.zig").expectVec;
const vec = @import("vec.zig");
const Vec2 = vec.Vec2;
const Config = @import("config.zig").Config;
const Trail = @import("trail.zig").Trail;
const Health = @import("health.zig").Health;
const Pool = @import("pool.zig").Pool;
const Event = @import("events.zig").Event;

pub const Leader = struct {
    pos: Vec2,
    /// Vetor unitário.
    heading: Vec2,
};

pub const Duck = struct {
    pos: Vec2,
    /// Segundos até poder atirar de novo.
    cooldown: f32 = 0,
};

pub const Enemy = struct {
    pos: Vec2,
    health: Health,
};

pub const Projectile = struct {
    pos: Vec2,
    velocity: Vec2,
    /// Distância que ainda pode voar.
    remaining: f32,
};

pub const World = struct {
    config: Config,
    leader: Leader,
    trail: Trail = .{},
    /// Na ordem da fila: o primeiro vem logo atrás da líder.
    ducks: std.MultiArrayList(Duck) = .empty,
    enemies: Pool(Enemy) = .{},
    projectiles: Pool(Projectile) = .{},
    /// Eventos do passo atual; o `sim` limpa no começo de cada passo.
    events: std.ArrayList(Event) = .empty,
    /// Toda a aleatoriedade vem daqui, criada com a seed.
    rng: std.Random.DefaultPrng,
    /// Vida da fila inteira.
    queue_health: Health,
    /// Segundos de invulnerabilidade que restam depois de um contato.
    invulnerable: f32 = 0,
    /// Segundos até o próximo inimigo.
    spawn_timer: f32,

    pub fn init(gpa: std.mem.Allocator, config: Config) !World {
        const start = config.leader.start;
        const heading = vec.normalize(config.leader.start_heading);
        var w: World = .{
            .config = config,
            .leader = .{ .pos = start, .heading = heading },
            .rng = .init(config.seed),
            .queue_health = .init(config.queue.life),
            .spawn_timer = config.spawner.interval,
        };
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
        self.enemies.deinit(gpa);
        self.projectiles.deinit(gpa);
        self.events.deinit(gpa);
    }

    /// Resumo do estado da simulação. Dois mundos com o mesmo hash estão no
    /// mesmo estado (para o teste de determinismo).
    pub fn hash(self: World) u64 {
        var h: std.hash.Wyhash = .init(0);
        feedVec(&h, self.leader.pos);
        feedVec(&h, self.leader.heading);
        feed(&h, self.rng.s);
        feed(&h, self.queue_health.current);
        feed(&h, self.invulnerable);
        feed(&h, self.spawn_timer);
        for (self.ducks.items(.pos)) |p| feedVec(&h, p);
        h.update(std.mem.sliceAsBytes(self.ducks.items(.cooldown)));

        const e = self.enemies.items;
        for (0..self.enemies.slots()) |i| {
            if (!self.enemies.isAlive(i)) continue;
            feed(&h, self.enemies.handleAt(i));
            feedVec(&h, e.items(.pos)[i]);
            feed(&h, e.items(.health)[i].current);
        }
        const p = self.projectiles.items;
        for (0..self.projectiles.slots()) |i| {
            if (!self.projectiles.isAlive(i)) continue;
            feedVec(&h, p.items(.pos)[i]);
            feedVec(&h, p.items(.velocity)[i]);
            feed(&h, p.items(.remaining)[i]);
        }
        return h.final();
    }

    /// Só tipos sem preenchimento (inteiros, floats, arrays deles, `Handle`).
    fn feed(h: *std.hash.Wyhash, value: anytype) void {
        h.update(std.mem.asBytes(&value));
    }

    fn feedVec(h: *std.hash.Wyhash, v: Vec2) void {
        feed(h, vec.toArray(v));
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

test "init: vida da fila cheia, sem inimigos nem flechas, spawn esperando o intervalo" {
    const cfg = config_example();
    var w: World = try .init(std.testing.allocator, cfg);
    defer w.deinit(std.testing.allocator);
    try std.testing.expectEqual(cfg.queue.life, w.queue_health.current);
    try std.testing.expectEqual(0, w.enemies.count);
    try std.testing.expectEqual(0, w.projectiles.count);
    try std.testing.expectEqual(cfg.spawner.interval, w.spawn_timer);
}

test "hash: mesmo estado, mesmo hash; qualquer mudança muda o hash" {
    const gpa = std.testing.allocator;
    var a: World = try .init(gpa, config_example());
    defer a.deinit(gpa);
    var b: World = try .init(gpa, config_example());
    defer b.deinit(gpa);
    try std.testing.expectEqual(a.hash(), b.hash());

    const h = try b.enemies.add(gpa, .{ .pos = .{ 1, 2 }, .health = .init(3) });
    try std.testing.expect(a.hash() != b.hash());
    _ = try a.enemies.add(gpa, .{ .pos = .{ 1, 2 }, .health = .init(3) });
    try std.testing.expectEqual(a.hash(), b.hash());

    b.enemies.items.items(.health)[b.enemies.slot(h).?].damage(1);
    try std.testing.expect(a.hash() != b.hash());
}

test "hash: muda com as flechas" {
    const gpa = std.testing.allocator;
    var a: World = try .init(gpa, config_example());
    defer a.deinit(gpa);
    var b: World = try .init(gpa, config_example());
    defer b.deinit(gpa);
    _ = try b.projectiles.add(gpa, .{ .pos = .{ 1, 2 }, .velocity = .{ 3, 4 }, .remaining = 5 });
    try std.testing.expect(a.hash() != b.hash());
}

test "hash: depende do gerador aleatório (seeds diferentes, hashes diferentes)" {
    const gpa = std.testing.allocator;
    var cfg = config_example();
    var a: World = try .init(gpa, cfg);
    defer a.deinit(gpa);
    cfg.seed += 1;
    var b: World = try .init(gpa, cfg);
    defer b.deinit(gpa);
    try std.testing.expect(a.hash() != b.hash());
}

fn initAndDeinit(gpa: std.mem.Allocator) !void {
    var w: World = try .init(gpa, config_example());
    w.deinit(gpa);
}

test "init: sem memória em qualquer alocação, devolve erro e não vaza" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initAndDeinit, .{});
}
