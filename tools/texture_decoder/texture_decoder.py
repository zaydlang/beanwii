from PIL import Image
import numpy as np
import sys

width = int(sys.argv[2])
height = int(sys.argv[3])
format = sys.argv[4]

framebuffer = np.zeros((height, width, 4), dtype=np.uint8)
framebuffer[:, :, 0] = 255
framebuffer[:, :, 3] = 255

with open('mem1.bin', 'rb') as f:
    binary_data1 = f.read()
with open('mem2.bin', 'rb') as f:
    binary_data2 = f.read()

def read(addr):
    if addr > 0x10000000:
        return binary_data2[addr - 0x10000000]
    else:
        return binary_data1[addr]

# base_address = 0x010137c0
# base_address = 17058240
base_address = int(sys.argv[1])

def interpolate(color1, color2, t):
    return (
        int(color1[0] + (color2[0] - color1[0]) * t),
        int(color1[1] + (color2[1] - color1[1]) * t),
        int(color1[2] + (color2[2] - color1[2]) * t),
        255
    )

def convert_0_to_7_to_0_to_255(value):
    return value * 36

def convert_0_to_15_to_0_to_255(value):
    return value * 17

def convert_0_to_31_to_0_to_255(value):
    return value * 8

def convert_0_to_63_to_0_to_255(value):
    return value * 4

def div_round_up(a, b):
    return (a + b - 1) // b

def convert_compressed():
    tiles_x = div_round_up(width, 8)
    tiles_y = div_round_up(height, 8)

    for tile_x in range(tiles_x):
        for tile_y in range(tiles_y):
            tile_number = tile_x + tile_y * tiles_x
            tile_address = base_address + tile_number * 32

            for texel_number in range(4):
                texel_address = tile_address + texel_number * 8

                rgb1 = read(texel_address)
                rgb2 = read(texel_address + 1)

                color1 = ((rgb1 & 0xf8) >> 3, ((rgb1 & 0x07) << 3) | ((rgb2 & 0xe0) >> 5), (rgb2 & 0x1f) >> 0, 255)

                rgb3 = read(texel_address + 2)
                rgb4 = read(texel_address + 3)

                # print(rgb1, rgb2, rgb3, rgb4)
                color2 = ((rgb3 & 0xf8) >> 3, ((rgb3 & 0x07) << 3) | ((rgb4 & 0xe0) >> 5), (rgb4 & 0x1f) >> 0, 255)

                color1 = (color1[0] * 8, color1[1] * 4, color1[2] * 8, 255)
                color2 = (color2[0] * 8, color2[1] * 4, color2[2] * 8, 255)

                x = tile_x * 8 + texel_number % 2 * 4
                y = tile_y * 8 + texel_number // 2 * 4

                colors = [
                    color1,
                    color2,
                    interpolate(color1, color2, 0.33),
                    interpolate(color1, color2, 0.66),
                ]
                # print(colors)

                address = texel_address
                bits = [
                    (read(address + 4) & 0xc0) >> 6,
                    (read(address + 4) & 0x30) >> 4,
                    (read(address + 4) & 0xc) >> 2,
                    read(address + 4) & 0x3,
                    (read(address + 5) & 0xc0) >> 6,
                    (read(address + 5) & 0x30) >> 4,
                    (read(address + 5) & 0xc) >> 2,
                    read(address + 5) & 0x3,
                    (read(address + 6) & 0xc0) >> 6,
                    (read(address + 6) & 0x30) >> 4,
                    (read(address + 6) & 0xc) >> 2,
                    read(address + 6) & 0x3,
                    (read(address + 7) & 0xc0) >> 6,
                    (read(address + 7) & 0x30) >> 4,
                    (read(address + 7) & 0xc) >> 2,
                    read(address + 7) & 0x3,
                ]

                fuck = 0

                for i in range(4):
                    for j in range(4):
                        color = colors[bits[fuck]]
                        framebuffer[y + i, x + j] = color
                        fuck += 1
                # exit(0)

def convert_ia8():
    tiles_x = width // 4
    tiles_y = height // 4

    current_address = base_address

    for tile_y in range(tiles_y):
        for tile_x in range(tiles_x):
            for fine_y in range(4):
                for fine_x in range(4):
                    intensity = read(current_address)
                    alpha = read(current_address + 1)
                    current_address += 2
                    intensity, alpha = alpha, intensity

                    x = tile_x * 4 + fine_x
                    y = tile_y * 4 + fine_y

                    framebuffer[y, x] = (intensity, intensity, intensity, alpha)

def convert_i4():
    tiles_x = width // 8
    tiles_y = height // 8

    current_address = base_address

    for tile_y in range(tiles_y):
        for tile_x in range(tiles_x):
            shit = False
            for fine_y in range(8):
                for fine_x in range(8):
                    value = read(current_address)

                    x = tile_x * 8 + fine_x
                    y = tile_y * 8 + fine_y

                    shit = not shit
                    if shit:
                        value = value >> 4
                    else:
                        value = value & 0xf
                        current_address += 1

                    intensity = value * 0x11
                    alpha = 0xff
                    framebuffer[y, x] = (intensity, intensity, intensity, alpha)


if format == 'compressed':
    convert_compressed()
elif format == 'ia8':
    convert_ia8()
elif format == 'i4':
    convert_i4()
else:
    print("???")
    exit(-1)
# Convert to Pillow Image
image = Image.fromarray(framebuffer, 'RGBA')


# save image
image.save('output.png')
