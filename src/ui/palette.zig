//! Paleta do jogo. Toda cor da tela vem daqui (ver `docs/guia-visual.md`).
const rl = @import("raylib");

fn hex(rgb: u24, alpha: u8) rl.Color {
    return .{ .r = @truncate(rgb >> 16), .g = @truncate(rgb >> 8), .b = @truncate(rgb), .a = alpha };
}

const opaque_alpha = 255;

pub const floor_a = hex(0x26262B, opaque_alpha);
pub const floor_b = hex(0x2D2D33, opaque_alpha);
pub const shadow = hex(0x000000, 140); // 55%
pub const ink = hex(0x16161A, opaque_alpha);
pub const leader = hex(0xFFF4DC, opaque_alpha);
pub const duckling = hex(0xFFD447, opaque_alpha);
pub const beak = hex(0xFF8A3D, opaque_alpha);
pub const archer = hex(0x3ECF8E, opaque_alpha);
pub const mage = hex(0x5B8CFF, opaque_alpha);
pub const enemy_coral = hex(0xFF4F78, opaque_alpha);
pub const highlight = hex(0xFFFFFF, 115); // 45%
pub const bar_back = hex(0x16161A, opaque_alpha);
pub const bar_fill = hex(0xFF3D5E, opaque_alpha);
pub const arrow = hex(0xF5F5F5, opaque_alpha);
pub const life = hex(0xFF4D6D, opaque_alpha);
pub const text = hex(0xFFFFFF, opaque_alpha);
pub const panel = hex(0x000000, 166); // 65%
