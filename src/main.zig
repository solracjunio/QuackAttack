//! Loop do jogo: só orquestra. A lógica fica no módulo `game`.
const rl = @import("raylib");
const game = @import("game");

const window_width = 960;
const window_height = 540;

pub fn main() void {
    _ = game;

    rl.initWindow(window_width, window_height, "QuackAtack");
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(.dark_green);
        rl.drawText("QuackAtack", 20, 20, 32, .yellow);
    }
}
