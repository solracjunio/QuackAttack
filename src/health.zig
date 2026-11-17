//! Vida de uma unidade. Só muda pelas funções deste módulo:
//! nunca fica negativa e nunca passa do máximo.
//!
//! O Zig não tem campos privados: os campos podem ser lidos à vontade,
//! mas escrever neles fora deste arquivo quebra a regra do módulo.
const std = @import("std");

pub const Health = struct {
    /// Somente leitura fora deste arquivo.
    current: u32,
    /// Somente leitura fora deste arquivo.
    max: u32,

    pub fn init(max: u32) Health {
        return .{ .current = max, .max = max };
    }

    pub fn damage(self: *Health, amount: u32) void {
        self.current -|= amount;
    }

    pub fn heal(self: *Health, amount: u32) void {
        self.current = @min(self.max, self.current +| amount);
    }

    pub fn isDead(self: Health) bool {
        return self.current == 0;
    }
};

test "init: começa com a vida cheia" {
    const h: Health = .init(10);
    try std.testing.expectEqual(10, h.current);
    try std.testing.expectEqual(10, h.max);
}

test "damage: tira a quantidade da vida" {
    var h: Health = .init(10);
    h.damage(3);
    try std.testing.expectEqual(7, h.current);
}

test "damage: para em 0 quando o dano passa da vida" {
    var h: Health = .init(10);
    h.damage(25);
    try std.testing.expectEqual(0, h.current);
}

test "heal: soma a quantidade à vida" {
    var h: Health = .init(10);
    h.damage(6);
    h.heal(4);
    try std.testing.expectEqual(8, h.current);
}

test "heal: para no máximo quando a cura passa dele" {
    var h: Health = .init(10);
    h.damage(2);
    h.heal(50);
    try std.testing.expectEqual(10, h.current);
}

test "isDead: verdadeiro só quando a vida chega a 0" {
    var h: Health = .init(10);
    h.damage(9);
    try std.testing.expect(!h.isDead());
    h.damage(1);
    try std.testing.expect(h.isDead());
}
