//! Relacionamentos entre entidades, com consulta por curinga:
//! `(Segue, líder)` e `(Mira, inimigo)`. Uma entidade tem no máximo um alvo
//! por tipo de relação.
const std = @import("std");
const Handle = @import("pool.zig").Handle;

pub const Kind = enum { segue, mira };

pub const Entity = union(enum) {
    leader,
    /// Posição na fila (patinhos só entram no fim, então o índice não muda).
    duck: u32,
    enemy: Handle,
};

/// Alvo procurado numa consulta: qualquer um, ou uma entidade específica.
pub const Pattern = union(enum) {
    any,
    is: Entity,

    fn matches(self: Pattern, e: Entity) bool {
        return switch (self) {
            .any => true,
            .is => |wanted| std.meta.eql(wanted, e),
        };
    }
};

pub const Relation = struct { kind: Kind, source: Entity, target: Entity };

pub const Registry = struct {
    /// Somente leitura fora deste arquivo.
    items: std.ArrayList(Relation) = .empty,

    pub fn deinit(self: *Registry, gpa: std.mem.Allocator) void {
        self.items.deinit(gpa);
    }

    /// Cria ou troca o alvo de `source` nesta relação.
    pub fn set(self: *Registry, gpa: std.mem.Allocator, kind: Kind, source: Entity, target: Entity) !void {
        if (self.find(kind, source)) |i| {
            self.items.items[i].target = target;
        } else {
            try self.items.append(gpa, .{ .kind = kind, .source = source, .target = target });
        }
    }

    fn find(self: Registry, kind: Kind, source: Entity) ?usize {
        for (self.items.items, 0..) |r, i| {
            if (r.kind == kind and std.meta.eql(r.source, source)) return i;
        }
        return null;
    }

    pub fn targetOf(self: Registry, kind: Kind, source: Entity) ?Entity {
        const i = self.find(kind, source) orelse return null;
        return self.items.items[i].target;
    }

    /// Desfaz a relação de `source`, se houver.
    pub fn clear(self: *Registry, kind: Kind, source: Entity) void {
        const i = self.find(kind, source) orelse return;
        _ = self.items.orderedRemove(i);
    }

    /// Percorre as relações `kind` cujo alvo casa com `pattern`.
    pub fn query(self: *const Registry, kind: Kind, pattern: Pattern) Query {
        return .{ .registry = self, .kind = kind, .pattern = pattern };
    }

    /// Desfaz todas as relações `kind` cujo alvo casa com `pattern`.
    pub fn clearWhere(self: *Registry, kind: Kind, pattern: Pattern) void {
        // Ordem estável (sem swapRemove): a ordem das relações entra no hash do mundo.
        var kept: usize = 0;
        for (self.items.items) |r| {
            if (r.kind == kind and pattern.matches(r.target)) continue;
            self.items.items[kept] = r;
            kept += 1;
        }
        self.items.shrinkRetainingCapacity(kept);
    }
};

pub const Query = struct {
    registry: *const Registry,
    kind: Kind,
    pattern: Pattern,
    next_index: usize = 0,

    pub fn next(self: *Query) ?Relation {
        const items = self.registry.items.items;
        while (self.next_index < items.len) {
            const r = items[self.next_index];
            self.next_index += 1;
            if (r.kind == self.kind and self.pattern.matches(r.target)) return r;
        }
        return null;
    }

    pub fn count(self: Query) usize {
        var copy = self;
        var n: usize = 0;
        while (copy.next()) |_| n += 1;
        return n;
    }
};

fn enemy(index: u32) Entity {
    return .{ .enemy = .{ .index = index, .generation = 0 } };
}

test "set e target: cada fonte tem um alvo por tipo de relação, e set troca o alvo" {
    const gpa = std.testing.allocator;
    var r: Registry = .{};
    defer r.deinit(gpa);
    try r.set(gpa, .segue, .{ .duck = 0 }, .leader);
    try r.set(gpa, .mira, .{ .duck = 0 }, enemy(3));
    try std.testing.expectEqual(Entity.leader, r.targetOf(.segue, .{ .duck = 0 }).?);
    try r.set(gpa, .mira, .{ .duck = 0 }, enemy(5));
    try std.testing.expectEqual(enemy(5), r.targetOf(.mira, .{ .duck = 0 }).?);
    try std.testing.expectEqual(null, r.targetOf(.mira, .{ .duck = 1 }));
}

test "clear: desfaz só a relação daquela fonte e daquele tipo" {
    const gpa = std.testing.allocator;
    var r: Registry = .{};
    defer r.deinit(gpa);
    try r.set(gpa, .segue, .{ .duck = 0 }, .leader);
    try r.set(gpa, .mira, .{ .duck = 0 }, enemy(3));
    try r.set(gpa, .mira, .{ .duck = 1 }, enemy(3));
    r.clear(.mira, .{ .duck = 0 });
    try std.testing.expectEqual(null, r.targetOf(.mira, .{ .duck = 0 }));
    try std.testing.expect(r.targetOf(.segue, .{ .duck = 0 }) != null);
    try std.testing.expect(r.targetOf(.mira, .{ .duck = 1 }) != null);
}

test "query: com alvo específico acha quem mira nele; com .any, todos que miram" {
    const gpa = std.testing.allocator;
    var r: Registry = .{};
    defer r.deinit(gpa);
    try r.set(gpa, .mira, .{ .duck = 0 }, enemy(3));
    try r.set(gpa, .mira, .{ .duck = 1 }, enemy(4));
    try r.set(gpa, .mira, .{ .duck = 2 }, enemy(3));
    try r.set(gpa, .segue, .{ .duck = 0 }, .leader);

    var it = r.query(.mira, .{ .is = enemy(3) });
    try std.testing.expectEqual(Entity{ .duck = 0 }, it.next().?.source);
    try std.testing.expectEqual(Entity{ .duck = 2 }, it.next().?.source);
    try std.testing.expectEqual(null, it.next());

    try std.testing.expectEqual(3, r.query(.mira, .any).count());
    try std.testing.expectEqual(1, r.query(.segue, .{ .is = .leader }).count());
    try std.testing.expectEqual(0, r.query(.segue, .{ .is = enemy(3) }).count());
}

test "query: a geração do handle conta (inimigo novo na mesma vaga não é o antigo)" {
    const gpa = std.testing.allocator;
    var r: Registry = .{};
    defer r.deinit(gpa);
    try r.set(gpa, .mira, .{ .duck = 0 }, enemy(3));
    const reused: Entity = .{ .enemy = .{ .index = 3, .generation = 1 } };
    try std.testing.expectEqual(0, r.query(.mira, .{ .is = reused }).count());
}

test "clearWhere: desfaz todas as relações com aquele alvo, e só elas" {
    const gpa = std.testing.allocator;
    var r: Registry = .{};
    defer r.deinit(gpa);
    try r.set(gpa, .mira, .{ .duck = 0 }, enemy(3));
    try r.set(gpa, .mira, .{ .duck = 1 }, enemy(4));
    try r.set(gpa, .mira, .{ .duck = 2 }, enemy(3));
    try r.set(gpa, .segue, .{ .duck = 0 }, .leader);
    r.clearWhere(.mira, .{ .is = enemy(3) });
    try std.testing.expectEqual(1, r.query(.mira, .any).count());
    try std.testing.expectEqual(enemy(4), r.targetOf(.mira, .{ .duck = 1 }).?);
    try std.testing.expectEqual(1, r.query(.segue, .any).count());
}
