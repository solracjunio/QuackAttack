//! Raiz da lógica do jogo. Não importa a raylib.
const std = @import("std");

pub const health = @import("health.zig");
pub const vec = @import("vec.zig");
pub const pool = @import("pool.zig");
pub const events = @import("events.zig");
pub const relations = @import("relations.zig");
pub const trail = @import("trail.zig");
pub const config = @import("config.zig");
pub const world = @import("world.zig");
pub const sim = @import("sim.zig");
pub const mover = @import("systems/mover.zig");
pub const seguir = @import("systems/seguir.zig");
pub const spawner = @import("systems/spawner.zig");
pub const perseguir = @import("systems/perseguir.zig");
pub const atacar = @import("systems/atacar.zig");
pub const projeteis = @import("systems/projeteis.zig");
pub const contato = @import("systems/contato.zig");
pub const aplicar_dano = @import("systems/aplicar_dano.zig");
pub const limpar_mortos = @import("systems/limpar_mortos.zig");
pub const testing = @import("testing.zig");

/// Faz o compilador analisar todas as declarações públicas, também dentro
/// dos tipos. Sem isso o Zig não compila funções que nenhum teste chama, e
/// elas somem da cobertura em vez de aparecer como linhas não cobertas.
/// (A std do 0.17 só tem o `refAllDecls`, que não é recursivo.)
/// Cuidado: um `pub const` que reexporte um tipo da std faria entrar a std.
fn refAllDeclsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |name| {
        const decl = @field(T, name);
        // mutation: disable — só decide o que entra na cobertura; nenhum teste de lógica depende disso
        if (@TypeOf(decl) == type) {
            switch (@typeInfo(decl)) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(decl),
                else => {},
            }
        } else _ = &decl;
    }
}

test {
    refAllDeclsRecursive(@This());
}
