//! Confere os arquivos de `data/` (pilar Editável: "dados válidos").
//! Roda no `zig build test-headless`, sem a raylib.
const std = @import("std");
const game = @import("game");

test "data/game.zon: lê e passa no validate" {
    const c: game.config.Config = @import("game.zon");
    if (game.config.validate(c)) |problem| {
        std.debug.print("data/game.zon: {s}\n", .{problem});
        return error.InvalidData;
    }
}
