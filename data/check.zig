//! Confere os arquivos de `data/` (pilar Editável: "dados válidos"), juntos:
//! referências entre eles também contam (ex.: classe inicial que não existe).
//! Roda no `zig build test-headless`, sem a raylib.
const std = @import("std");
const game = @import("game");

test "data/game.zon e data/classes.zon: leem e passam no validate" {
    var c: game.config.Config = @import("game.zon");
    c.classes = @import("classes.zon");
    if (game.config.validate(c)) |problem| {
        std.debug.print("data/: {s}\n", .{problem});
        return error.InvalidData;
    }
}
