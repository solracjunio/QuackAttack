//! Pool de entidades com handle (índice + geração). Um handle guardado nunca
//! aponta para a entidade errada: remover aumenta a geração da vaga, e o
//! handle antigo passa a não valer mais, mesmo se a vaga for reaproveitada.
const std = @import("std");

pub const Handle = struct { index: u32, generation: u32 };

pub fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Dados por vaga, separados por campo. Vagas mortas ficam com lixo:
        /// percorra com `isAlive`. Somente leitura fora deste arquivo, exceto
        /// os valores dos campos das vagas vivas.
        items: std.MultiArrayList(T) = .empty,
        generations: std.ArrayList(u32) = .empty,
        alive: std.ArrayList(bool) = .empty,
        free: std.ArrayList(u32) = .empty,
        /// Quantas entidades vivas.
        count: u32 = 0,

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.items.deinit(gpa);
            self.generations.deinit(gpa);
            self.alive.deinit(gpa);
            self.free.deinit(gpa);
        }

        pub fn add(self: *Self, gpa: std.mem.Allocator, item: T) !Handle {
            // Reserva tudo antes de mudar algo: se faltar memória, o pool fica como estava.
            // A lista de livres cabe todas as vagas, para `remove` nunca precisar alocar.
            try self.items.ensureUnusedCapacity(gpa, 1);
            try self.generations.ensureUnusedCapacity(gpa, 1);
            try self.alive.ensureUnusedCapacity(gpa, 1);
            try self.free.ensureTotalCapacity(gpa, self.items.len + 1);

            const s: usize = if (self.free.pop()) |reused| reused else blk: {
                self.items.appendAssumeCapacity(item);
                self.generations.appendAssumeCapacity(0);
                self.alive.appendAssumeCapacity(undefined); // preenchido logo abaixo
                break :blk self.items.len - 1;
            };
            self.items.set(s, item);
            self.alive.items[s] = true;
            self.count += 1;
            return self.handleAt(s);
        }

        /// Remove a entidade. Handle velho ou já removido: não faz nada.
        pub fn remove(self: *Self, h: Handle) void {
            const s = self.slot(h) orelse return;
            self.alive.items[s] = false;
            self.generations.items[s] +%= 1;
            self.free.appendAssumeCapacity(@intCast(s));
            self.count -= 1;
        }

        /// Vaga da entidade, ou null se o handle não vale mais.
        pub fn slot(self: Self, h: Handle) ?usize {
            const s: usize = h.index;
            if (s >= self.items.len) return null;
            if (!self.alive.items[s] or self.generations.items[s] != h.generation) return null;
            return s;
        }

        pub fn isAlive(self: Self, s: usize) bool {
            return self.alive.items[s];
        }

        pub fn handleAt(self: Self, s: usize) Handle {
            return .{ .index = @intCast(s), .generation = self.generations.items[s] };
        }

        /// Total de vagas (vivas e mortas), para percorrer com `isAlive`.
        pub fn slots(self: Self) usize {
            return self.items.len;
        }
    };
}

const Thing = struct { value: u32 };

test "add e slot: o handle leva à entidade" {
    const gpa = std.testing.allocator;
    var p: Pool(Thing) = .{};
    defer p.deinit(gpa);
    _ = try p.add(gpa, .{ .value = 7 });
    const h = try p.add(gpa, .{ .value = 9 });
    const s = p.slot(h) orelse return error.TestExpectedSlot;
    try std.testing.expectEqual(9, p.items.items(.value)[s]);
    try std.testing.expectEqual(2, p.count);
}

test "slot: handle com índice além das vagas não vale (nem quebra)" {
    const gpa = std.testing.allocator;
    var p: Pool(Thing) = .{};
    defer p.deinit(gpa);
    _ = try p.add(gpa, .{ .value = 7 });
    try std.testing.expectEqual(null, p.slot(.{ .index = 1, .generation = 0 }));
}

test "remove: o handle deixa de valer" {
    const gpa = std.testing.allocator;
    var p: Pool(Thing) = .{};
    defer p.deinit(gpa);
    const h = try p.add(gpa, .{ .value = 7 });
    p.remove(h);
    try std.testing.expectEqual(null, p.slot(h));
    try std.testing.expectEqual(0, p.count);
    try std.testing.expect(!p.isAlive(h.index));
}

test "add depois de remove: reaproveita a vaga com outra geração" {
    const gpa = std.testing.allocator;
    var p: Pool(Thing) = .{};
    defer p.deinit(gpa);
    const old = try p.add(gpa, .{ .value = 7 });
    p.remove(old);
    const new = try p.add(gpa, .{ .value = 8 });
    try std.testing.expectEqual(old.index, new.index);
    try std.testing.expect(new.generation != old.generation);
    try std.testing.expectEqual(null, p.slot(old));
    try std.testing.expectEqual(8, p.items.items(.value)[p.slot(new).?]);
    try std.testing.expectEqual(1, p.slots());
}

test "remove com handle velho não remove a entidade nova da vaga" {
    const gpa = std.testing.allocator;
    var p: Pool(Thing) = .{};
    defer p.deinit(gpa);
    const old = try p.add(gpa, .{ .value = 7 });
    p.remove(old);
    const new = try p.add(gpa, .{ .value = 8 });
    p.remove(old);
    try std.testing.expect(p.slot(new) != null);
    try std.testing.expectEqual(1, p.count);
}

fn addTwoRemoveOneAddOne(gpa: std.mem.Allocator) !void {
    var p: Pool(Thing) = .{};
    defer p.deinit(gpa);
    const a = try p.add(gpa, .{ .value = 1 });
    _ = try p.add(gpa, .{ .value = 1 });
    p.remove(a);
    _ = try p.add(gpa, .{ .value = 1 });
}

test "add: sem memória em qualquer alocação, devolve erro e não vaza" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, addTwoRemoveOneAddOne, .{});
}
