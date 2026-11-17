//! Montagem da imagem em camadas (`docs/guia-visual.md`, "Brilho"):
//! fundo (chão e sombras) → brilho → atores e HUD. O brilho fica embaixo dos
//! personagens, como uma auréola, e não borra o contorno deles.
const rl = @import("raylib");
const World = @import("game").world.World;
const scene = @import("scene.zig");
const hud = @import("hud.zig");
const glow_mod = @import("glow.zig");
const Glow = glow_mod.Glow;
const flipped = glow_mod.flipped;

pub const Renderer = struct {
    /// Chão e sombras, em resolução baixa.
    ground: rl.RenderTexture2D,
    /// Atores e HUD, em resolução baixa, sobre fundo transparente.
    actors: rl.RenderTexture2D,
    glow: Glow,
    camera: rl.Camera2D,
    /// A janela inteira.
    screen: rl.Rectangle,

    pub fn init(width: i32, height: i32) !Renderer {
        const low_w = @divTrunc(width, scene.pixel_scale);
        const low_h = @divTrunc(height, scene.pixel_scale);
        const ground = try rl.loadRenderTexture(low_w, low_h);
        errdefer rl.unloadRenderTexture(ground);
        const actors = try rl.loadRenderTexture(low_w, low_h);
        errdefer rl.unloadRenderTexture(actors);
        // Pixel grande: ampliar sem suavizar.
        rl.setTextureFilter(ground.texture, .point);
        rl.setTextureFilter(actors.texture, .point);
        return .{
            .ground = ground,
            .actors = actors,
            .glow = try .init(low_w, low_h),
            .camera = .{ .offset = .{ .x = 0, .y = 0 }, .target = .{ .x = 0, .y = 0 }, .rotation = 0, .zoom = 1.0 / @as(f32, scene.pixel_scale) },
            .screen = .{ .x = 0, .y = 0, .width = @floatFromInt(width), .height = @floatFromInt(height) },
        };
    }

    pub fn deinit(self: Renderer) void {
        self.glow.deinit();
        rl.unloadRenderTexture(self.actors);
        rl.unloadRenderTexture(self.ground);
    }

    /// Desenha as camadas e calcula o brilho. Chamar fora de `beginDrawing`.
    pub fn render(self: Renderer, w: World) void {
        rl.beginTextureMode(self.ground);
        rl.beginMode2D(self.camera);
        scene.drawGround(w);
        rl.endMode2D();
        rl.endTextureMode();

        rl.beginTextureMode(self.actors);
        rl.clearBackground(.blank);
        beginLayerBlend();
        rl.beginMode2D(self.camera);
        scene.drawActors(w);
        rl.endMode2D();
        hud.draw(w);
        rl.endBlendMode();
        rl.endTextureMode();

        self.glow.update(self.actors.texture);
    }

    /// Monta a imagem na janela: fundo, brilho, atores. Chamar dentro de `beginDrawing`.
    pub fn present(self: Renderer) void {
        const origin: rl.Vector2 = .{ .x = 0, .y = 0 };
        rl.drawTexturePro(self.ground.texture, flipped(self.ground.texture), self.screen, origin, 0, .white);
        self.glow.draw(self.screen);
        // A camada dos atores sai com a cor já multiplicada pelo alfa (ver `beginLayerBlend`).
        rl.beginBlendMode(.alpha_premultiply);
        rl.drawTexturePro(self.actors.texture, flipped(self.actors.texture), self.screen, origin, 0, .white);
        rl.endBlendMode();
    }
};

/// Mistura para desenhar sobre uma camada transparente. Com a mistura padrão,
/// o alfa também é multiplicado (0,45 vira 0,2), e um brilho translúcido
/// sobre um corpo opaco "fura" o personagem. Aqui o alfa acumula como numa
/// pilha de papéis (`a = src + dst * (1 - src)`), e a cor sai multiplicada
/// pelo alfa.
fn beginLayerBlend() void {
    const gl = rl.gl;
    gl.rlSetBlendFactorsSeparate(gl.rl_src_alpha, gl.rl_one_minus_src_alpha, gl.rl_one, gl.rl_one_minus_src_alpha, gl.rl_func_add, gl.rl_func_add);
    rl.beginBlendMode(.custom_separate);
}
