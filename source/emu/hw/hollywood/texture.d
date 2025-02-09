module emu.hw.hollywood.texture;

import dklib.khash;
import emu.hw.hollywood.hollywood;
import emu.hw.memory.strategy.memstrategy;
import util.bitop;
import util.log;
import util.number;
struct TextureDescriptor {
    size_t width;
    size_t height;

    TextureType type;
    u32 base_address;
    Color* texture;

    TextureWrap wrap_s;
    TextureWrap wrap_t;

    int dualtex_matrix_slot;
    bool dualtex_normal_enable;

    int tex_matrix_slot;
}

enum TextureType {
    I4 = 0,
    IA8 = 3,
    Compressed = 14,
}

struct Color {
    u8 b;
    u8 g;
    u8 r;
    u8 a;
}

enum TextureWrap {
    Clamp = 0,
    Repeat = 1,
    Mirror = 2,
}

alias TextureCache = khash!(u64, Color[]);
TextureCache texture_cache;

size_t size_of_texture(TextureDescriptor descriptor) {
    final switch (descriptor.type) {
        case TextureType.I4:
            return descriptor.width * descriptor.height / 2;
        case TextureType.IA8:
            return descriptor.width * descriptor.height * 2;
        case TextureType.Compressed:
            return descriptor.width * descriptor.height / 2;
    }
}

u64 calculate_texture_hash(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;

    u64 hash = 0;

    hash ^= width;
    hash ^= height;
    hash ^= base_address;
    hash ^= cast(u64) descriptor.type;

    return hash;
}

Color[] load_texture_i4(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;

    auto texture = new Color[width * height];

    int tiles_x = cast(int) width  / 8;
    int tiles_y = cast(int) height / 8;

    u32 current_address = base_address;
    for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
    for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
        for (int fine_y = 0; fine_y < 8; fine_y++) {
        for (int fine_x = 0; fine_x < 8; fine_x++) {
            auto x = tile_x * 8 + fine_x;
            auto y = tile_y * 8 + fine_y;

            auto value = mem.paddr_read_u8(cast(u32) current_address);

            if (x % 2 == 0) {
                texture[x * height + y] = Color(
                    ((value & 0xf0) >> 4) * 0x11 == 0 ? 0 : 255,
                    ((value & 0xf0) >> 4) * 0x11 == 0 ? 0 : 255,
                    ((value & 0xf0) >> 4) * 0x11 == 0 ? 0 : 255,
                    ((value & 0xf0) >> 4) * 0x11 == 0 ? 0 : 255,
                );
            } else {
                texture[x * height + y] = Color(
                    (value & 0x0f) * 0x11 == 0 ? 0 : 255,
                    (value & 0x0f) * 0x11 == 0 ? 0 : 255,
                    (value & 0x0f) * 0x11 == 0 ? 0 : 255,
                    (value & 0x0f) * 0x11 == 0 ? 0 : 255,
                );
    
                current_address += 1;
            }
        }
        }
    }
    }

    return texture;
}

Color[] load_texture_ia8(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;

    auto texture = new Color[width * height];

    int tiles_x = cast(int) width  / 4;
    int tiles_y = cast(int) height / 4;

    u32 current_address = base_address;
    for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
    for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
        for (int fine_y = 0; fine_y < 4; fine_y++) {
        for (int fine_x = 0; fine_x < 4; fine_x++) {
            auto value = mem.paddr_read_u16(current_address);
            current_address += 2;

            u8 intensity = cast(u8) value.bits(0, 7);
            u8 alpha     = cast(u8) value.bits(8, 15);
            
            auto x = tile_x * 4 + fine_x;
            auto y = tile_y * 4 + fine_y;

            texture[x * height + y] = Color(
                intensity,
                intensity,
                intensity,
                alpha
            );
        }
        }
    }
    }

    return texture;
}
Color[] load_texture_compressed(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;
    
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

            bool has_transparency = mem.paddr_read_u16(texel_address) <= mem.paddr_read_u16(texel_address + 2);
            int[4][4] colors = has_transparency ? 
            [
                color1,
                color2,
                interpolate(color1, color2, 0.5),
                [0, 0, 0, 0]
            ]
            :
            [
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
                    cast(u8) colors[bits[i + j * 4]][3]
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

Color[] load_texture(TextureDescriptor descriptor, Mem mem) {
    log_hollywood("Loading texture: %s", descriptor);

    u64 hash = calculate_texture_hash(descriptor, mem);
    auto cache = texture_cache.require(hash, null);
    if (cache != null) {
        return cache;
    }

    Color[] result;
    switch (descriptor.type) {
        case TextureType.I4:
            result = load_texture_i4(descriptor, mem); break;
        case TextureType.IA8:
            result = load_texture_ia8(descriptor, mem); break;
        case TextureType.Compressed:
            result = load_texture_compressed(descriptor, mem); break;
        default:
            error_hollywood("Unsupported texture type: %d", descriptor.type);
    }

    texture_cache[hash] = result;
    return result;
}