module emu.hw.hollywood.texture;

import bindbc.opengl;
import dklib.khash;
import emu.hw.hollywood.gl_objects;
import emu.hw.hollywood.hollywood;
import emu.hw.memory.strategy.memstrategy;
import std.file;
import std.format;
import util.bitop;
import util.log;
import util.lru;
import util.number;
import util.page_allocator;
import util.perfect_bloom_filter_dict;
import std.math;
import std.algorithm;

struct TextureDescriptor {
    size_t width;
    size_t height;

    TextureType type;
    u32 base_address;
    Color* texture;

    TextureWrap wrap_s;
    TextureWrap wrap_t;

    int dualtex_matrix_slot;
    int tex_matrix_slot;

    u8 min_filter;
    u8 mag_filter;
    float min_lod;
    float max_lod;
    float lod_bias;
    bool edge_lod;
    bool bias_clamp;
    u8 max_aniso;
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

    struct TextureCacheEntry {
        int texture_id;
        u32 address;
        int max_level;
    }

    struct LoadedTexture {
        int texture_id;
        int max_level;
    }
    
final class TextureManager {
    alias TextureCache = ClockCache!(u64, TextureCacheEntry, 256);
    TextureCache texture_cache;
    PageAllocator!(Color, false) texture_allocator;
    uint[256] gl_texture_ids;
    PerfectBloomFilterDict!GLuint gpu_texture_cache;
    int[GLuint] texture_max_level;
    
    this() {
        glGenTextures(256, gl_texture_ids.ptr);
        log_texture("Pre-allocated 256 GL texture objects");
        gpu_texture_cache = new PerfectBloomFilterDict!GLuint();
    }

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
        hash ^= (cast(u64) descriptor.min_filter) << 32;
        hash ^= (cast(u64) descriptor.mag_filter) << 36;
        hash ^= (cast(u64) cast(int)(descriptor.min_lod * 256)) << 40;
        hash ^= (cast(u64) cast(int)(descriptor.max_lod * 256)) << 48;
        hash ^= (cast(u64) cast(int)(descriptor.lod_bias * 256)) << 54;
        hash ^= (cast(u64) descriptor.edge_lod) << 60;
        hash ^= (cast(u64) descriptor.max_aniso) << 61;

        return hash;
    }

    Color[] load_texture_rgb565(TextureDescriptor descriptor, Mem mem) {
        auto width = descriptor.width;
        auto height = descriptor.height;
        auto base_address = descriptor.base_address;

        auto texture = texture_allocator.allocate_array(width * height);

        int tiles_x = div_roundup(cast(int) width,  4);
        int tiles_y = div_roundup(cast(int) height, 4);

        u32 current_address = base_address;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 4; fine_x++) {
                auto x = tile_x * 4 + fine_x;
                auto y = tile_y * 4 + fine_y;

                auto value = mem.physical_read_u16(cast(u32) current_address);
                current_address += 2;

                if (x >= width || y >= height) {
                    continue;
                }

                texture[y * width + x] = Color(
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

        auto texture = texture_allocator.allocate_array(width * height);

        int tiles_x = div_roundup(cast(int) width,  4);
        int tiles_y = div_roundup(cast(int) height, 4);

        u32 current_address = base_address;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 4; fine_x++) {
                auto x = tile_x * 4 + fine_x;
                auto y = tile_y * 4 + fine_y;

                auto value = mem.physical_read_u16(cast(u32) current_address);
                current_address += 2;

                if (x >= width || y >= height) {
                    continue;
                }

                if (value & 0x8000) {
                    texture[y * width + x] = Color(
                        cast(u8) (value.bits(0,   4) << 3),
                        cast(u8) (value.bits(5,   9) << 3),
                        cast(u8) (value.bits(10, 14) << 3),
                        255
                    );
                } else {
                    texture[y * width + x] = Color(
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

        auto texture = texture_allocator.allocate_array(width * height);

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

                auto value = mem.physical_read_u8(cast(u32) current_address);

                if (x % 2 == 0) {
                    texture[y * width + x] = Color(
                        ((value & 0xf0) >> 4) * 0x11,
                        ((value & 0xf0) >> 4) * 0x11,
                        ((value & 0xf0) >> 4) * 0x11,
                        ((value & 0xf0) >> 4) * 0x11,
                    );
                } else {
                    texture[y * width + x] = Color(
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

        auto texture = texture_allocator.allocate_array(width * height);

        int tiles_x = div_roundup(cast(int) width,  8);
        int tiles_y = div_roundup(cast(int) height, 4);

        u32 current_address = base_address;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 8; fine_x++) {
                auto x = tile_x * 8 + fine_x;
                auto y = tile_y * 4 + fine_y;

                auto value = mem.physical_read_u8(cast(u32) current_address);

                current_address += 1;

                if (x >= width || y >= height) {
                    continue;
                }

                texture[y * width + x] = Color(value, value, value, value);
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

        auto texture = texture_allocator.allocate_array(width * height);

        int tiles_x = div_roundup(cast(int) width,  8);
        int tiles_y = div_roundup(cast(int) height, 4);

        u32 current_address = base_address;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 8; fine_x++) {
                auto x = tile_x * 8 + fine_x;
                auto y = tile_y * 4 + fine_y;

                auto value = mem.physical_read_u8(cast(u32) current_address);
                current_address += 1;

                if (x >= width || y >= height) {
                    continue;
                }

                texture[y * width + x] = Color(
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

        auto texture = texture_allocator.allocate_array(width * height);

        int tiles_x = div_roundup(cast(int) width,  4);
        int tiles_y = div_roundup(cast(int) height, 4);

        u32 current_address = base_address;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 4; fine_x++) {
                auto x = tile_x * 4 + fine_x;
                auto y = tile_y * 4 + fine_y;

                auto value = mem.physical_read_u16(current_address);
                current_address += 2;

                if (x >= width || y >= height) {
                    continue;
                }

                u8 intensity = cast(u8) value.bits(0, 7);
                u8 alpha     = cast(u8) value.bits(8, 15);

                texture[y * width + x] = Color(
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
        
        auto texture = texture_allocator.allocate_array(width * height);

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

                u32 rgb1 = mem.physical_read_u8(texel_address);
                u32 rgb2 = mem.physical_read_u8(texel_address + 1);
                int[4] color1 = [(rgb1 & 0xf8) >> 3, ((rgb1 & 0x07) << 3) | ((rgb2 & 0xe0) >> 5), (rgb2 & 0x1f) >> 0, 255];
            
                u32 rgb3 = mem.physical_read_u8(texel_address + 2);
                u32 rgb4 = mem.physical_read_u8(texel_address + 3);
                int[4] color2 = [(rgb3 & 0xf8) >> 3, ((rgb3 & 0x07) << 3) | ((rgb4 & 0xe0) >> 5), (rgb4 & 0x1f) >> 0, 255];

                color1 = [color1[0] * 8, color1[1] * 4, color1[2] * 8, 255];
                color2 = [color2[0] * 8, color2[1] * 4, color2[2] * 8, 255];

                int x = tile_x * 8 + texel_number % 2 * 4;
                int y = tile_y * 8 + texel_number / 2 * 4;

                bool has_transparency = mem.physical_read_u16(texel_address) <= mem.physical_read_u16(texel_address + 2);
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
                    mem.physical_read_u8(texel_address + 4),
                    mem.physical_read_u8(texel_address + 5),
                    mem.physical_read_u8(texel_address + 6),
                    mem.physical_read_u8(texel_address + 7)
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

                    auto texture_index = (y + j) * width + (x + i);
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

        auto texture = texture_allocator.allocate_array(width * height);

        int tiles_x = div_roundup(cast(int) width,  4);
        int tiles_y = div_roundup(cast(int) height, 4);

        u32 current_address = base_address;
        for (int tile_y = 0; tile_y < tiles_y; tile_y++) {
        for (int tile_x = 0; tile_x < tiles_x; tile_x++) {
            auto ba_address = current_address;
            auto rg_address = current_address + 32;

            for (int fine_y = 0; fine_y < 4; fine_y++) {
            for (int fine_x = 0; fine_x < 4; fine_x++) {
                auto x = tile_x * 4 + fine_x;
                auto y = tile_y * 4 + fine_y;

                if (x >= width || y >= height) {
                    continue;
                }

                texture[y * width + x] = Color(
                    mem.physical_read_u8(rg_address + 1),
                    mem.physical_read_u8(rg_address + 0),
                    mem.physical_read_u8(ba_address + 1),
                    mem.physical_read_u8(ba_address + 0)
                );

                ba_address += 2;
                rg_address += 2;
            }
            }

            current_address += 64;
        }
        }

        return texture;
    }

    LoadedTexture load_texture(TextureDescriptor descriptor, Mem mem, GlObjectManager gl_object_manager) {
        if (texture_allocator.length == 0) {
            texture_allocator = PageAllocator!(Color, false)(0);
        }

        u32 cached_texture_id;
        if (gpu_texture_cache.get(cast(u64) descriptor.base_address, cached_texture_id)) {
            int cached_level = 0;
            if (cached_texture_id in texture_max_level) {
                cached_level = texture_max_level[cached_texture_id];
            }
            return LoadedTexture(cast(int) cached_texture_id, cached_level);
        }

        u64 hash = calculate_texture_hash(descriptor, mem);
        long cached_index = texture_cache.lookup(hash);
        if (cached_index != -1) {
            TextureCacheEntry entry = texture_cache.entries[cached_index].value;
            return LoadedTexture(entry.texture_id, entry.max_level);
        }

        log_texture("Loading texture: %s", descriptor);
    
        size_t cache_index = texture_cache.insert(hash);
        uint texture_id = gl_texture_ids[cache_index];
        
        int level_count = upload_texture_levels(texture_id, descriptor, mem);

        TextureCacheEntry entry = TextureCacheEntry(cast(int) texture_id, descriptor.base_address, level_count - 1);
        texture_cache.entries[cache_index].value = entry;

        texture_max_level[texture_id] = level_count - 1;
        // dump_texture_to_file(result, format("tex_%s_%s_%d_%d", descriptor.type, hash, descriptor.width, descriptor.height));
        return LoadedTexture(cast(int) texture_id, level_count - 1);
    }
    
    void invalidate_texture_at_address(u32 address) {
        foreach (ref entry; texture_cache.entries) {
            if (entry.valid && entry.value.address == address) {
                entry.valid = false;
                texture_cache.count--;
                log_texture("Invalidated texture cache at address 0x%08x", address);
            }
        }
    }

    void cache_gpu_texture(u32 address, GLuint texture_id, int max_level = 0) {
        gpu_texture_cache.set(address, texture_id);
        texture_max_level[texture_id] = max_level;
        log_texture("Cached GPU texture %d at address 0x%08x", texture_id, address);
    }

private:
    Color[] decode_texture_level(TextureDescriptor descriptor, Mem mem) {
        final switch (descriptor.type) {
            case TextureType.I4:       return load_texture_i4(descriptor, mem);
            case TextureType.IA4:      return load_texture_ia4(descriptor, mem);
            case TextureType.I8:       return load_texture_i8(descriptor, mem);
            case TextureType.IA8:      return load_texture_ia8(descriptor, mem);
            case TextureType.Compressed: return load_texture_compressed(descriptor, mem);
            case TextureType.RGB565:   return load_texture_rgb565(descriptor, mem);
            case TextureType.RGB5A3:   return load_texture_rgb5a3(descriptor, mem);
            case TextureType.RGBA32:   return load_texture_rgba32(descriptor, mem);
        }
        error_hollywood("Unsupported texture type: %d", descriptor.type);
        return null;
    }

    void block_info(TextureType type, out size_t block_w, out size_t block_h, out size_t bytes_per_block) {
        final switch (type) {
            case TextureType.I4:
            case TextureType.Compressed:
                block_w = 8; block_h = 8; bytes_per_block = 32; break;
            case TextureType.I8:
            case TextureType.IA4:
                block_w = 8; block_h = 4; bytes_per_block = 32; break;
            case TextureType.IA8:
            case TextureType.RGB565:
            case TextureType.RGB5A3:
                block_w = 4; block_h = 4; bytes_per_block = 64; break;
            case TextureType.RGBA32:
                block_w = 4; block_h = 4; bytes_per_block = 128; break;
        }
    }

    size_t calculate_mip_level_size(size_t width, size_t height, TextureType type) {
        size_t block_w, block_h, bytes_per_block;
        block_info(type, block_w, block_h, bytes_per_block);
        size_t blocks_x = div_roundup(cast(int) width, cast(int) block_w);
        size_t blocks_y = div_roundup(cast(int) height, cast(int) block_h);
        return blocks_x * blocks_y * bytes_per_block;
    }

    int upload_texture_levels(uint texture_id, TextureDescriptor descriptor, Mem mem) {
        glBindTexture(GL_TEXTURE_2D, texture_id);

        bool wants_mips = descriptor.min_filter >= 2;

        int max_possible_levels = 1;
        size_t tmp_w = descriptor.width;
        size_t tmp_h = descriptor.height;
        while (tmp_w > 1 || tmp_h > 1) {
            tmp_w = tmp_w > 1 ? (tmp_w >> 1) : 1;
            tmp_h = tmp_h > 1 ? (tmp_h >> 1) : 1;
            max_possible_levels++;
        }

        int max_level_from_desc = cast(int) floor(descriptor.max_lod + 0.5f);
        if (max_level_from_desc < 0) {
            max_level_from_desc = 0;
        }

        int level_limit = wants_mips ? min(max_possible_levels, max_level_from_desc + 1) : 1;

        size_t width = descriptor.width;
        size_t height = descriptor.height;
        size_t offset = 0;
        int level = 0;
        for (; level < level_limit; level++) {
            TextureDescriptor level_desc = descriptor;
            level_desc.width = width;
            level_desc.height = height;
            level_desc.base_address = descriptor.base_address + cast(u32) offset;

            auto data = decode_texture_level(level_desc, mem);
            glTexImage2D(GL_TEXTURE_2D, level, GL_RGBA, cast(int) width, cast(int) height, 0, GL_BGRA, GL_UNSIGNED_BYTE, data.ptr);

            offset += calculate_mip_level_size(width, height, descriptor.type);
            width = width > 1 ? width / 2 : 1;
            height = height > 1 ? height / 2 : 1;
        }

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_BASE_LEVEL, 0);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAX_LEVEL, level - 1);

        return level;
    }
}
    
void dump_texture_to_file(Color[] texture, string name) {
    string filename = format("texture_dumps/%s.rgba", name);
    std.file.write(filename, cast(u8[]) texture);
}
