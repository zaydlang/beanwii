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
    TexcoordSource texcoord_source;

    int dualtex_matrix_slot;
    bool normalize_before_dualtex;

    int tex_matrix_slot;
}

enum TextureType {
    I4 = 0,
    I8 = 1,
    IA4 = 2,
    IA8 = 3,
    RGB565 = 4,
    RGB5A3 = 5,
    RGBA32 = 6,
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

enum TexcoordSource {
    Geometry = 0,
    Normal = 1,
    Colors = 2,
    BinormalT = 3,
    BinormalB = 4,
    Tex0 = 5,
    Tex1 = 6,
    Tex2 = 7,
    Tex3 = 8,
    Tex4 = 9,
    Tex5 = 10,
    Tex6 = 11,
    Tex7 = 12,
}

alias TextureCache = khash!(u64, Color[]);
TextureCache texture_cache;

size_t size_of_texture(TextureDescriptor descriptor) {
    final switch (descriptor.type) {
        case TextureType.I4:
            return div_roundup(descriptor.width * descriptor.height, 2);
        case TextureType.I8:
            return descriptor.width * descriptor.height;
        case TextureType.IA4:
            return descriptor.width * descriptor.height;
        case TextureType.IA8:
            return descriptor.width * descriptor.height * 2;
        case TextureType.Compressed:
            return div_roundup(descriptor.width * descriptor.height, 2);
        case TextureType.RGB565:
            return descriptor.width * descriptor.height * 2;
        case TextureType.RGB5A3:
            return descriptor.width * descriptor.height * 2;
        case TextureType.RGBA32:
            return descriptor.width * descriptor.height * 4;
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

Color[] load_texture_rgb565(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;

    auto texture = new Color[width * height];

    int tiles_x = div_roundup(cast(int) width,  4);
    int tiles_y = div_roundup(cast(int) height, 4);

    u32 current_address = base_address;
    for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
    for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
        for (int fine_y = 0; fine_y < 4; fine_y++) {
        for (int fine_x = 0; fine_x < 4; fine_x++) {
            auto x = tile_x * 4 + fine_x;
            auto y = tile_y * 4 + fine_y;

            auto value = mem.paddr_read_u16(cast(u32) current_address);
            current_address += 2;

            texture[x * height + y] = Color(
                (value & 0x001f) << 3,
                (value & 0x07e0) >> 3,
                (value & 0xf800) >> 8,
                255
            );
        }
        }
    }
    }

    return texture;
}

Color[] load_texture_rgb5a3(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;

    auto texture = new Color[width * height];

    int tiles_x = div_roundup(cast(int) width,  4);
    int tiles_y = div_roundup(cast(int) height, 4);

    u32 current_address = base_address;
    for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
    for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
        for (int fine_y = 0; fine_y < 4; fine_y++) {
        for (int fine_x = 0; fine_x < 4; fine_x++) {
            auto x = tile_x * 4 + fine_x;
            auto y = tile_y * 4 + fine_y;

            auto value = mem.paddr_read_u16(cast(u32) current_address);
            current_address += 2;

            if (value & 0x8000) {
                texture[x * height + y] = Color(
                    cast(u8) (value.bits(0,   4) << 3),
                    cast(u8) (value.bits(5,   9) << 3),
                    cast(u8) (value.bits(10, 14) << 3),
                    255
                );
            } else {
                texture[x * height + y] = Color(
                    cast(u8) (value.bits(0, 3)   << 4),
                    cast(u8) (value.bits(4, 7)   << 4),
                    cast(u8) (value.bits(8, 11)  << 4),
                    cast(u8) (value.bits(12, 14) << 5)
                );
            }
        }
        }
    }
    }

    return texture;
}

Color[] load_texture_i4(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;

    auto texture = new Color[width * height];

    int tiles_x = div_roundup(cast(int) width,  8);
    int tiles_y = div_roundup(cast(int) height, 8);

    u32 current_address = base_address;
    for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
    for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
        for (int fine_y = 0; fine_y < 8; fine_y++) {
        for (int fine_x = 0; fine_x < 8; fine_x++) {
            auto x = tile_x * 8 + fine_x;
            auto y = tile_y * 8 + fine_y;

            if (x >= width || y >= height) {
                if (x % 2 != 0) {
                    current_address += 1;
                }

                continue;
            }

            auto value = mem.paddr_read_u8(cast(u32) current_address);

            if (x % 2 == 0) {
                texture[x * height + y] = Color(
                    ((value & 0xf0) >> 4) * 0x11,
                    ((value & 0xf0) >> 4) * 0x11,
                    ((value & 0xf0) >> 4) * 0x11,
                    ((value & 0xf0) >> 4) * 0x11,
                );
            } else {
                texture[x * height + y] = Color(
                    (value & 0x0f) * 0x11,
                    (value & 0x0f) * 0x11,
                    (value & 0x0f) * 0x11,
                    (value & 0x0f) * 0x11,
                );
    
                current_address += 1;
            }
        }
        }
    }
    }

    return texture;
}

Color[] load_texture_i8(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;

    auto texture = new Color[width * height];

    int tiles_x = div_roundup(cast(int) width,  8);
    int tiles_y = div_roundup(cast(int) height, 4);

    u32 current_address = base_address;
    for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
    for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
        for (int fine_y = 0; fine_y < 8; fine_y++) {
        for (int fine_x = 0; fine_x < 8; fine_x++) {
            auto x = tile_x * 8 + fine_x;
            auto y = tile_y * 8 + fine_y;

            if (x >= width || y >= height) {
                continue;
            }

            auto value = mem.paddr_read_u8(cast(u32) current_address);

            texture[x * height + y] = Color(value, value, value, 0xFF);

            current_address += 1;
        }
        }
    }
    }

    return texture;
}

Color[] load_texture_ia4(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    log_hollywood("Loading IA4 texture: %s", descriptor);
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;

    auto texture = new Color[width * height];

    int tiles_x = div_roundup(cast(int) width,  8);
    int tiles_y = div_roundup(cast(int) height, 4);

    u32 current_address = base_address;
    for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
    for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
        for (int fine_y = 0; fine_y < 4; fine_y++) {
        for (int fine_x = 0; fine_x < 8; fine_x++) {
            auto x = tile_x * 8 + fine_x;
            auto y = tile_y * 4 + fine_y;

            auto value = mem.paddr_read_u8(cast(u32) current_address);
            current_address += 1;

            if (x >= width || y >= height) {
                continue;
            }

            texture[x * height + y] = Color(
                ((value & 0x0f) >> 0) * 0x11,
                ((value & 0x0f) >> 0) * 0x11,
                ((value & 0x0f) >> 0) * 0x11,
                ((value & 0xf0) >> 4) * 0x11,
            );
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

    int tiles_x = div_roundup(cast(int) width,  4);
    int tiles_y = div_roundup(cast(int) height, 4);

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

            if (x >= width || y >= height) {
                continue;
            }

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

    int tiles_x = div_roundup(cast(int) width,  8);
    int tiles_y = div_roundup(cast(int) height, 8);

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
                if (x + i >= width || y + j >= height) {
                    continue;
                }

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

Color[] load_texture_rgba32(TextureDescriptor descriptor, Mem mem) {
    auto width = descriptor.width;
    auto height = descriptor.height;
    auto base_address = descriptor.base_address;

    auto texture = new Color[width * height];

    int tiles_x = div_roundup(cast(int) width,  4);
    int tiles_y = div_roundup(cast(int) height, 4);

    u32 current_address = base_address;
    for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
    for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
        auto ra_address = current_address;
        auto gb_address = current_address + 32;

        for (int fine_y = 0; fine_y < 4; fine_y++) {
        for (int fine_x = 0; fine_x < 4; fine_x++) {
            auto x = tile_x * 4 + fine_x;
            auto y = tile_y * 4 + fine_y;

            texture[x * height + y] = Color(
                mem.paddr_read_u8(ra_address + 1),
                mem.paddr_read_u8(gb_address + 0),
                mem.paddr_read_u8(gb_address + 1),
                mem.paddr_read_u8(ra_address + 0)
            );

            ra_address += 2;
            gb_address += 2;
        }
        }

        current_address += 64;
    }
    }

    return texture;
}

Color[] load_texture(TextureDescriptor descriptor, Mem mem) {
    log_hollywood("Loading texture %d: %s", mem.mmio.hollywood.shape_groups.length, descriptor);

    u64 hash = calculate_texture_hash(descriptor, mem);
    auto cache = texture_cache.require(hash, null);
    if (cache != null) {
        return cache;
    }

    log_hollywood("Loading texture: %s", descriptor);
 
    Color[] result;
    switch (descriptor.type) {
        case TextureType.I4:
            result = load_texture_i4(descriptor, mem); break;
        case TextureType.IA4:
            result = load_texture_ia4(descriptor, mem); break;
        case TextureType.I8:
            result = load_texture_i8(descriptor, mem); break;
        case TextureType.IA8:
            result = load_texture_ia8(descriptor, mem); break;
        case TextureType.Compressed:
            result = load_texture_compressed(descriptor, mem); break;
        case TextureType.RGB565:
            result = load_texture_rgb565(descriptor, mem); break;
        case TextureType.RGB5A3:
            result = load_texture_rgb5a3(descriptor, mem); break;
        case TextureType.RGBA32:
            result = load_texture_rgba32(descriptor, mem); break;
        default:
            error_hollywood("Unsupported texture type: %d", descriptor.type);
    }

    texture_cache[hash] = result;
    return result;
}