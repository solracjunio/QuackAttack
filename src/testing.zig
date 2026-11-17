//! Ajudas para os testes da lógica. Não importa nada do jogo (evita ciclos).
const std = @import("std");

// magic: allow — tolerância de comparação de floats nos testes
pub const tolerance = 1e-3;

/// Compara vetores coordenada a coordenada, com `tolerance`.
/// `expected` pode ser uma tupla, como `.{ 1, 0 }`.
pub fn expectVec(expected: anytype, actual: anytype) !void {
    const T = @TypeOf(actual);
    const want: T = expected;
    inline for (0..@typeInfo(T).vector.len) |i| {
        try std.testing.expectApproxEqAbs(want[i], actual[i], tolerance);
    }
}
