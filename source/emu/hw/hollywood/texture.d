module emu.hw.hollywood.texture;

import emu.hw.hollywood.hollywood;
import emu.hw.memory.strategy.memstrategy;
import util.log;
import util.number;

struct TextureDescriptor {
    size_t width;
    size_t height;

    TextureType type;
    u32 base_address;
    Color* texture;
}

enum TextureType {
    Compressed = 14,
}

struct Color {
    u8 b;
    u8 g;
    u8 r;
}

Color[] load_texture(TextureDescriptor descriptor, Mem mem) {
    auto type = descriptor.type;
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;
    
    if (type != TextureType.Compressed) {
        log_hollywood("Unsupported texture type: %d", type);
    }

    auto texture = new Color[width * height];

    int tiles_x = cast(int) width  / 8;
    int tiles_y = cast(int) height / 8;

    int[4] interpolate(int[4] color_a, int[4] color_b, double c) {
        return [
            color_a[0] + cast(int) ((color_b[0] - color_a[0]) * c),
            color_a[1] + cast(int) ((color_b[1] - color_a[1]) * c),
            color_a[2] + cast(int) ((color_b[2] - color_a[2]) * c),
            255
        ];
    }

    for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
    for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        int tile_number = tile_x + tile_y * tiles_x;
        int tile_address = base_address + tile_number * 32;

        for (int texel_number = 0; texel_number < 4; texel_number++) {
            int texel_address = tile_address + texel_number * 8;

            u32 rgb1 = mem.paddr_read_u8(texel_address);
            u32 rgb2 = mem.paddr_read_u8(texel_address + 1);
            int[4] color1 = [(rgb1 & 0xf8) >> 3, ((rgb1 & 0x07) << 3) | ((rgb2 & 0xe0) >> 5), (rgb2 & 0x1f) >> 0, 255];
        
            u32 rgb3 = mem.paddr_read_u8(texel_address + 2);
            u32 rgb4 = mem.paddr_read_u8(texel_address + 3);
            int[4] color2 = [(rgb3 & 0xf8) >> 3, ((rgb3 & 0x07) << 3) | ((rgb4 & 0xe0) >> 5), (rgb4 & 0x1f) >> 0, 255];

            color1 = [color1[0] * 8, color1[1] * 4, color1[2] * 8, 255];
            color2 = [color2[0] * 8, color2[1] * 4, color2[2] * 8, 255];

            int x = tile_x * 8 + texel_number % 2 * 4;
            int y = tile_y * 8 + texel_number / 2 * 4;

            int[4][4] colors = [
                color1,
                color2,
                interpolate(color1, color2, 0.33),
                interpolate(color1, color2, 0.66)
            ];

            int[4] texels = [
                mem.paddr_read_u8(texel_address + 4),
                mem.paddr_read_u8(texel_address + 5),
                mem.paddr_read_u8(texel_address + 6),
                mem.paddr_read_u8(texel_address + 7)
            ];

            int[16] bits = [
                (texels[0] & 0xc0) >> 6,
                (texels[0] & 0x30) >> 4,
                (texels[0] & 0x0c) >> 2,
                (texels[0] & 0x03) >> 0,
                (texels[1] & 0xc0) >> 6,
                (texels[1] & 0x30) >> 4,
                (texels[1] & 0x0c) >> 2,
                (texels[1] & 0x03) >> 0,
                (texels[2] & 0xc0) >> 6,
                (texels[2] & 0x30) >> 4,
                (texels[2] & 0x0c) >> 2,
                (texels[2] & 0x03) >> 0,
                (texels[3] & 0xc0) >> 6,
                (texels[3] & 0x30) >> 4,
                (texels[3] & 0x0c) >> 2,
                (texels[3] & 0x03) >> 0,
            ];

            for (int i = 0; i < 4; i++) {
            for (int j = 0; j < 4; j++) {
                auto texture_index = (x + i) * height + (y + j);
                texture[texture_index] = Color(
                    cast(u8) colors[bits[i + j * 4]][2],
                    cast(u8) colors[bits[i + j * 4]][1],
                    cast(u8) colors[bits[i + j * 4]][0],
                );
            }
            }
        }
    }
    }

    // if (texture.length > 100)
    // log_hollywood("SHIT: %s", texture[0..100]);
    return texture;
}