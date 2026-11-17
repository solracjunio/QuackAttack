//! Raiz da lógica do jogo. Não importa a raylib.
pub const health = @import("health.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
