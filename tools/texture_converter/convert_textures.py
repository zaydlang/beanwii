#!/usr/bin/env python3

import os
from PIL import Image

for filename in os.listdir('texture_dumps'):
    if filename.endswith('.rgba'):
        parts = filename.replace('.rgba', '').split('_')
        width = int(parts[2].split('x')[0])
        height = int(parts[2].split('x')[1])
        
        with open(f'texture_dumps/{filename}', 'rb') as f:
            data = f.read()
        
        rgba_data = bytearray()
        for i in range(0, len(data), 4):
            b, g, r, a = data[i:i+4]
            rgba_data.extend([r, g, b, a])
        
        img = Image.frombytes('RGBA', (height, width), bytes(rgba_data))
        img = img.rotate(90, expand=True)
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
        img.save(f'texture_dumps/{filename.replace(".rgba", ".png")}')
        print(f'Converted {filename}')