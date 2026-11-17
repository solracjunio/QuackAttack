//! Desenho do mundo, seguindo `docs/guia-visual.md`. Coordenadas do mundo;
//! a câmera do `main.zig` reduz para a resolução da cena (pixel grande).
const rl = @import("raylib");
const game = @import("game");
const World = game.world.World;
const Vec2 = game.vec.Vec2;
const vec = game.vec;
const palette = @import("palette.zig");
const classes = game.classes;

/// A cena é desenhada com 1/`pixel_scale` da resolução da janela e ampliada.
pub const pixel_scale = 2;

const floor_tile = 32;
// Sombra: elipse um pouco abaixo do corpo, mais larga que alta (frações do raio).
const shadow_drop = 0.85;
const shadow_width = 1.05;
const shadow_height = 0.5;
// Inimigo: gota arredondada mais larga que alta (frações do raio).
const blob_width = 1.15;
const blob_top = 0.95;
const blob_bottom = 0.75;
const blob_roundness = 0.8;
const round_segments = 8;
const eye_spread = 0.32;
const eye_raise = 0.1;
const eye_size = 0.14;
const shine_offset = 0.45;
const shine_size = 0.18;
const bar_drop = 1.45;
const bar_height = 4;
// Pato: bico, olho e acessório (frações do raio).
const beak_length = 0.75;
const beak_width = 0.45;
const duck_eye_ahead = 0.35;
const duck_eye_side = 0.35;
const duck_eye_size = 0.16;
const hat_height = 0.9;
const hat_width = 0.55;
const hat_base = 0.65;
// Chapéu de mago: mais alto, com aba.
const wizard_height = 1.3;
const wizard_width = 0.5;
const brim_width = 0.85;
const brim_height = 0.18;
// Anel do feitiço em área: aparece logo depois do lançamento e some.
const spell_flash_seconds = 0.35;
const spell_ring_thick = 4;
const spell_ring_alpha = 0.55;
const ring_segments = 48;
// Flecha.
const arrow_back = 14;
const arrow_thick = 4;
const arrow_head = 8;
// Piscar da fila invulnerável.
const blink_rate = 10;
const blink_alpha = 0.35;

/// Camada de fundo: chão e sombras. Fica embaixo do brilho.
pub fn drawGround(w: World) void {
    drawFloor(w.config.world.width, w.config.world.height);
    drawShadows(w);
}

/// Camada dos atores: inimigos, flechas e a fila. Fica por cima do brilho,
/// para o contorno continuar nítido.
pub fn drawActors(w: World) void {
    drawSpells(w);
    drawEnemies(w);
    drawArrows(w);
    drawQueue(w);
}

fn drawFloor(width: f32, height: f32) void {
    const cols: i32 = @intFromFloat(@ceil(width / floor_tile));
    const rows: i32 = @intFromFloat(@ceil(height / floor_tile));
    var row: i32 = 0;
    while (row < rows) : (row += 1) {
        var col: i32 = 0;
        while (col < cols) : (col += 1) {
            const color = if (@mod(row + col, 2) == 0) palette.floor_a else palette.floor_b;
            rl.drawRectangle(col * floor_tile, row * floor_tile, floor_tile, floor_tile, color);
        }
    }
}

fn drawShadows(w: World) void {
    const cfg = w.config;
    const e = w.enemies;
    for (e.items.items(.pos), 0..) |pos, i| {
        if (e.isAlive(i)) shadow(pos, cfg.enemy.radius);
    }
    for (w.ducks.items(.pos)) |pos| shadow(pos, cfg.queue.radius);
    shadow(w.leader.pos, cfg.leader.radius);
}

fn shadow(pos: Vec2, r: f32) void {
    rl.drawEllipseV(.{ .x = pos[0], .y = pos[1] + r * shadow_drop }, r * shadow_width, r * shadow_height, palette.shadow);
}

fn drawEnemies(w: World) void {
    const r = w.config.enemy.radius;
    const e = w.enemies;
    const items = e.items.slice();
    for (items.items(.pos), items.items(.health), 0..) |pos, health, i| {
        if (!e.isAlive(i)) continue;
        const body: rl.Rectangle = .{
            .x = pos[0] - r * blob_width,
            .y = pos[1] - r * blob_top,
            .width = r * blob_width * 2,
            .height = r * (blob_top + blob_bottom),
        };
        rl.drawRectangleRounded(body, blob_roundness, round_segments, palette.enemy_coral);
        // Brilho no alto, à esquerda, e a carinha.
        rl.drawCircleV(toRl(pos + vec.scale(.{ -1, -1 }, r * shine_offset)), r * shine_size, palette.highlight);
        rl.drawCircleV(toRl(pos + vec.scale(.{ -eye_spread, -eye_raise }, r)), r * eye_size, palette.ink);
        rl.drawCircleV(toRl(pos + vec.scale(.{ eye_spread, -eye_raise }, r)), r * eye_size, palette.ink);
        healthBar(pos, r, health.current, health.max);
    }
}

fn healthBar(pos: Vec2, r: f32, current: u32, max: u32) void {
    const width = r * blob_width * 2;
    const x = pos[0] - width / 2;
    const y = pos[1] + r * bar_drop;
    rl.drawRectangleV(.{ .x = x, .y = y }, .{ .x = width, .y = bar_height }, palette.bar_back);
    const fraction = @as(f32, @floatFromInt(current)) / @as(f32, @floatFromInt(max));
    rl.drawRectangleV(.{ .x = x, .y = y }, .{ .x = width * fraction, .y = bar_height }, palette.bar_fill);
}

fn drawArrows(w: World) void {
    const p = w.projectiles;
    const items = p.items.slice();
    for (items.items(.pos), items.items(.velocity), 0..) |pos, velocity, i| {
        if (!p.isAlive(i)) continue;
        const dir = vec.normalize(velocity);
        const tail = pos - vec.scale(dir, arrow_back);
        rl.drawLineEx(toRl(tail), toRl(pos), arrow_thick, palette.arrow);
        const side: Vec2 = .{ -dir[1], dir[0] };
        triangle(
            pos + vec.scale(dir, arrow_head),
            pos + vec.scale(side, arrow_head / 2),
            pos - vec.scale(side, arrow_head / 2),
            palette.arrow,
        );
    }
}

fn drawQueue(w: World) void {
    const cfg = w.config;
    const fade: f32 = if (blinking(w.invulnerable)) blink_alpha else 1;
    const ducks = w.ducks.items(.pos);
    // Do fim da fila para a frente: quem vem antes fica por cima.
    var i = ducks.len;
    while (i > 0) {
        i -= 1;
        // Cada filhote olha para o pato da frente.
        const ahead = if (i == 0) w.leader.pos else ducks[i - 1];
        const facing = facingTo(ducks[i], ahead, w.leader.heading);
        const class = cfg.classes[w.ducks.items(.class)[i]];
        duck(ducks[i], facing, cfg.queue.radius, palette.duckling, fade);
        hat(ducks[i], cfg.queue.radius, class.look, fade);
    }
    duck(w.leader.pos, w.leader.heading, cfg.leader.radius, palette.leader, fade);
}

fn blinking(invulnerable: f32) bool {
    return invulnerable > 0 and @mod(invulnerable * blink_rate, 1) < 0.5;
}

/// Direção de `from` para `to`; se estiverem no mesmo ponto, `fallback`.
fn facingTo(from: Vec2, to: Vec2, fallback: Vec2) Vec2 {
    if (vec.length(to - from) == 0) return fallback;
    return vec.normalize(to - from);
}

fn duck(pos: Vec2, facing: Vec2, r: f32, body: rl.Color, fade: f32) void {
    const side: Vec2 = .{ -facing[1], facing[0] };
    // Bico primeiro, saindo por baixo do corpo.
    triangle(
        pos + vec.scale(facing, r + r * beak_length * 0.5),
        pos + vec.scale(facing, r * 0.5) + vec.scale(side, r * beak_width),
        pos + vec.scale(facing, r * 0.5) - vec.scale(side, r * beak_width),
        palette.beak.fade(fade),
    );
    rl.drawCircleV(toRl(pos), r, body.fade(fade));
    rl.drawCircleV(toRl(pos + vec.scale(.{ -1, -1 }, r * shine_offset)), r * shine_size, palette.highlight.fade(fade));
    // Olho do lado de cima (o lado de y menor), para o pato não ficar "de costas".
    const eye_side = if (side[1] <= 0) side else -side;
    const eye = pos + vec.scale(facing, r * duck_eye_ahead) + vec.scale(eye_side, r * duck_eye_side);
    rl.drawCircleV(toRl(eye), r * duck_eye_size, palette.ink.fade(fade));
}

/// Cor de destaque da classe na paleta.
fn accentColor(accent: classes.Accent) rl.Color {
    return switch (accent) {
        .green => palette.archer,
        .blue => palette.mage,
    };
}

/// Acessório da classe no alto da cabeça (guia visual: classe = acessório).
fn hat(pos: Vec2, r: f32, look: classes.Look, fade: f32) void {
    const color = accentColor(look.accent).fade(fade);
    const base_y = pos[1] - r * hat_base;
    switch (look.hat) {
        .hood => triangle(
            .{ pos[0], base_y - r * hat_height },
            .{ pos[0] - r * hat_width, base_y },
            .{ pos[0] + r * hat_width, base_y },
            color,
        ),
        .pointed => {
            rl.drawRectangleV(
                .{ .x = pos[0] - r * brim_width, .y = base_y - r * brim_height },
                .{ .x = r * brim_width * 2, .y = r * brim_height * 2 },
                color,
            );
            triangle(
                .{ pos[0] + r * wizard_width * 0.5, base_y - r * wizard_height },
                .{ pos[0] - r * wizard_width, base_y },
                .{ pos[0] + r * wizard_width, base_y },
                color,
            );
        },
    }
}

/// Anel do feitiço em área, logo depois do lançamento (a recarga acabou de recomeçar).
fn drawSpells(w: World) void {
    const ducks = w.ducks.slice();
    for (ducks.items(.pos), ducks.items(.cooldown), ducks.items(.class)) |pos, cooldown, class_index| {
        const class = w.config.classes[class_index];
        const spell = switch (class.attack) {
            .area => |a| a,
            else => continue,
        };
        const since_cast = spell.cooldown - cooldown;
        if (cooldown == 0 or since_cast > spell_flash_seconds) continue;
        const fade = (1 - since_cast / spell_flash_seconds) * spell_ring_alpha;
        const color = accentColor(class.look.accent);
        rl.drawCircleV(toRl(pos), spell.radius, color.fade(fade * 0.35));
        rl.drawRing(toRl(pos), spell.radius - spell_ring_thick, spell.radius, 0, 360, ring_segments, color.fade(fade));
    }
}

/// `drawTriangle` só desenha na ordem anti-horária da raylib (com y para
/// baixo, produto vetorial negativo). Ajusta a ordem para qualquer rotação.
fn triangle(a: Vec2, b: Vec2, c: Vec2, color: rl.Color) void {
    const ab = b - a;
    const ac = c - a;
    const cross = ab[0] * ac[1] - ab[1] * ac[0];
    if (cross < 0) {
        rl.drawTriangle(toRl(a), toRl(b), toRl(c), color);
    } else {
        rl.drawTriangle(toRl(a), toRl(c), toRl(b), color);
    }
}

pub fn toRl(v: Vec2) rl.Vector2 {
    return .{ .x = v[0], .y = v[1] };
}
