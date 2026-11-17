//! Brilho (bloom) da cena inteira, seguindo `docs/guia-visual.md`.
//!
//! Um shader pega só o que é claro na cena já desenhada (personagens,
//! inimigos, tiros, HUD), borra numa textura menor e o resultado é somado por
//! cima da imagem. Chão e sombras ficam abaixo do limite e não brilham, então
//! todo item novo ganha brilho sem código extra.
const rl = @import("raylib");

/// A textura do brilho tem 1/`downscale` da resolução da cena: brilho mais
/// largo e mais barato.
const downscale = 2;

/// Força do brilho somado por cima (0 a 1).
const strength = 0.4;

const fragment_shader =
    \\#version 330
    \\in vec2 fragTexCoord;
    \\in vec4 fragColor;
    \\uniform sampler2D texture0;
    \\uniform vec2 texel;
    \\out vec4 finalColor;
    \\// Só brilha o que passa deste brilho (0 a 1): chão e sombras ficam de fora.
    \\const float threshold = 0.45;
    \\// Distância entre as amostras, em pixels da cena.
    \\const float spread = 1.0;
    \\const int radius = 5;
    \\void main() {
    \\    vec3 sum = vec3(0.0);
    \\    float total = 0.0;
    \\    for (int x = -radius; x <= radius; x++) {
    \\        for (int y = -radius; y <= radius; y++) {
    \\            float weight = exp(-float(x * x + y * y) / 10.0);
    \\            vec3 c = texture(texture0, fragTexCoord + vec2(x, y) * texel * spread).rgb;
    \\            float bright = max(c.r, max(c.g, c.b));
    \\            sum += c * smoothstep(threshold, 1.0, bright) * weight;
    \\            total += weight;
    \\        }
    \\    }
    \\    finalColor = vec4(sum / total * 1.2, 1.0);
    \\}
;

pub const Glow = struct {
    shader: rl.Shader,
    target: rl.RenderTexture2D,

    /// `width` e `height`: tamanho da cena (a textura em resolução baixa).
    pub fn init(width: i32, height: i32) !Glow {
        const shader = try rl.loadShaderFromMemory(null, fragment_shader);
        errdefer rl.unloadShader(shader);
        const target = try rl.loadRenderTexture(@divTrunc(width, downscale), @divTrunc(height, downscale));
        // Bilinear: o brilho é para ser macio, ao contrário da cena.
        rl.setTextureFilter(target.texture, .bilinear);
        const texel = [2]f32{ 1.0 / @as(f32, @floatFromInt(width)), 1.0 / @as(f32, @floatFromInt(height)) };
        rl.setShaderValue(shader, rl.getShaderLocation(shader, "texel"), &texel, .vec2);
        return .{ .shader = shader, .target = target };
    }

    pub fn deinit(self: Glow) void {
        rl.unloadRenderTexture(self.target);
        rl.unloadShader(self.shader);
    }

    /// Calcula o brilho da `scene` (fora de `beginDrawing`).
    pub fn update(self: Glow, scene: rl.Texture2D) void {
        rl.beginTextureMode(self.target);
        defer rl.endTextureMode();
        rl.clearBackground(.black);
        rl.beginShaderMode(self.shader);
        defer rl.endShaderMode();
        rl.drawTexturePro(scene, flipped(scene), whole(self.target.texture), .{ .x = 0, .y = 0 }, 0, .white);
    }

    /// Soma o brilho por cima do que já está na tela, cobrindo `dst`.
    pub fn draw(self: Glow, dst: rl.Rectangle) void {
        rl.beginBlendMode(.additive);
        defer rl.endBlendMode();
        const tint: rl.Color = .{ .r = 255, .g = 255, .b = 255, .a = @intFromFloat(strength * 255) };
        rl.drawTexturePro(self.target.texture, flipped(self.target.texture), dst, .{ .x = 0, .y = 0 }, 0, tint);
    }
};

/// Texturas de render vêm de cabeça para baixo (OpenGL): altura negativa.
pub fn flipped(t: rl.Texture2D) rl.Rectangle {
    return .{ .x = 0, .y = 0, .width = @floatFromInt(t.width), .height = -@as(f32, @floatFromInt(t.height)) };
}

fn whole(t: rl.Texture2D) rl.Rectangle {
    return .{ .x = 0, .y = 0, .width = @floatFromInt(t.width), .height = @floatFromInt(t.height) };
}
