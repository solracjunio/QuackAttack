//! Eventos como objetos: os sistemas não se chamam, só acrescentam eventos
//! na fila do mundo. A fila é processada uma vez por passo, sem callbacks.
const std = @import("std");
const Handle = @import("pool.zig").Handle;

/// Quem leva dano: a fila (uma vida só para todos) ou um inimigo.
pub const Target = union(enum) {
    queue,
    enemy: Handle,
};

pub const Event = union(enum) {
    damage: struct { target: Target, amount: u32 },
    died: struct { enemy: Handle },
    /// `wave` é o número da onda que acabou (1 = a primeira).
    wave_ended: struct { wave: u32 },
    /// Patinho novo no fim da fila: posição dele e índice da classe.
    duck_joined: struct { duck: u32, class: u32 },
};

/// Texto do evento para o overlay de debug. O `switch` é exaustivo: um tipo
/// de evento novo sem texto aqui não compila (pilar Depurável).
pub fn describe(e: Event, buf: []u8) []const u8 {
    var w: std.Io.Writer = .fixed(buf);
    write(e, &w) catch {}; // buffer cheio: fica com o que coube
    return w.buffered();
}

fn write(e: Event, w: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (e) {
        .damage => |d| switch (d.target) {
            .queue => try w.print("dano {d} na fila", .{d.amount}),
            .enemy => |h| try w.print("dano {d} no inimigo #{d}.{d}", .{ d.amount, h.index, h.generation }),
        },
        .died => |d| try w.print("morreu inimigo #{d}.{d}", .{ d.enemy.index, d.enemy.generation }),
        .wave_ended => |d| try w.print("fim da onda {d}", .{d.wave}),
        .duck_joined => |d| try w.print("patinho {d} entrou (classe {d})", .{ d.duck, d.class }),
    }
}

test "describe: texto de cada tipo de evento" {
    var buf: [64]u8 = undefined;
    const h: Handle = .{ .index = 4, .generation = 2 };
    try std.testing.expectEqualStrings("dano 3 na fila", describe(.{ .damage = .{ .target = .queue, .amount = 3 } }, &buf));
    try std.testing.expectEqualStrings("dano 1 no inimigo #4.2", describe(.{ .damage = .{ .target = .{ .enemy = h }, .amount = 1 } }, &buf));
    try std.testing.expectEqualStrings("morreu inimigo #4.2", describe(.{ .died = .{ .enemy = h } }, &buf));
}

test "describe: fim de onda e patinho novo" {
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("fim da onda 3", describe(.{ .wave_ended = .{ .wave = 3 } }, &buf));
    try std.testing.expectEqualStrings("patinho 5 entrou (classe 1)", describe(.{ .duck_joined = .{ .duck = 5, .class = 1 } }, &buf));
}

test "describe: buffer pequeno corta o texto em vez de falhar" {
    var buf: [5]u8 = undefined;
    try std.testing.expectEqualStrings("morre", describe(.{ .died = .{ .enemy = .{ .index = 4, .generation = 2 } } }, &buf));
}
