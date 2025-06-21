module ui.sdl.color;

import util.number;

Color from_hex(uint hex) {
    return Color(
        ((hex >> 16) & 0xFF) / 255.0f,
        ((hex >>  8) & 0xFF) / 255.0f,
        ((hex >>  0) & 0xFF) / 255.0f,
        1.0f
    );
}

struct Color {
    float r;
    float g;
    float b;
    float a;
}

Color darken(Color color, float factor) {
    factor = 1.0f - factor;
    return Color(color.r * factor, color.g * factor, color.b * factor, color.a);
}

Color lighten(Color color, float factor) {
    factor = 1.0f + factor;
    return Color(color.r * factor, color.g * factor, color.b * factor, color.a);
}