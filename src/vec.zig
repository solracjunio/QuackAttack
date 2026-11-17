//! Vetor 2D: o `@Vector` do Zig já soma, subtrai e multiplica por elemento.
const std = @import("std");
const expectVec = @import("testing.zig").expectVec;

pub const Vec2 = @Vector(2, f32); // magic: allow — dimensão do vetor (2D), não é balanceamento

/// As coordenadas sem preenchimento. No backend próprio do Zig, um
/// `@Vector(2, f32)` ocupa 16 bytes, e os 8 de alinhamento têm lixo (no LLVM
/// ocupa 8): nunca leia os bytes do vetor direto.
pub const Array = [@typeInfo(Vec2).vector.len]f32;

pub fn toArray(v: Vec2) Array {
    return v;
}

pub fn scale(v: Vec2, s: f32) Vec2 {
    return v * @as(Vec2, @splat(s));
}

pub fn length(v: Vec2) f32 {
    return @sqrt(@reduce(.Add, v * v));
}

/// Mesmo sentido, comprimento 1.
pub fn normalize(v: Vec2) Vec2 {
    return scale(v, 1 / length(v));
}

/// Gira `v` em `angle` radianos, no sentido anti-horário.
pub fn rotate(v: Vec2, angle: f32) Vec2 {
    const c = @cos(angle);
    const s = @sin(angle);
    return .{ v[0] * c - v[1] * s, v[0] * s + v[1] * c };
}

test "length: comprimento euclidiano" {
    try std.testing.expectApproxEqAbs(5.0, length(.{ 3, 4 }), @import("testing.zig").tolerance);
}

test "rotate: um quarto de volta leva x em y" {
    try expectVec(.{ 0, 1 }, rotate(.{ 1, 0 }, std.math.pi / 2.0));
    try expectVec(.{ -1, 0 }, rotate(.{ 0, 1 }, std.math.pi / 2.0));
}

test "scale: multiplica as duas coordenadas" {
    try expectVec(.{ 6, -3 }, scale(.{ 2, -1 }, 3));
}

test "normalize: mantém o sentido e deixa o comprimento em 1" {
    try expectVec(.{ 0.6, 0.8 }, normalize(.{ 3, 4 }));
}

test "toArray: só as coordenadas, sem o preenchimento do vetor" {
    try std.testing.expectEqual(Array{ 3, -4 }, toArray(.{ 3, -4 }));
    // O tamanho do vetor depende do backend: 16 bytes no do Zig, 8 no LLVM.
    try std.testing.expect(@sizeOf(Array) <= @sizeOf(Vec2));
}
