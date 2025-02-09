module ui.sdl.font;

import bindbc.opengl;
import bindbc.freetype;
import std.algorithm;
import ui.sdl.color;
import util.log;

struct RenderedTextHandle {
    private {
        uint vao;
        uint vbo;
    }
}

struct Character {
    uint texture;
    long advance;
    int bearing_x;
    int bearing_y;
    int size_x;
    int size_y;
}

final class Font {
    Character[char] characters;
    GLint font_shader;

    this(string path, FT_Library ft, GLint font_shader) {
        this.font_shader = font_shader;

        glUseProgram(font_shader);
        
        auto position_location = glGetAttribLocation(font_shader, "in_Position");
        glEnableVertexAttribArray(position_location);
        glVertexAttribPointer(position_location, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*) 0);
        
        auto texcoord_location = glGetAttribLocation(font_shader, "in_UV");
        glEnableVertexAttribArray(texcoord_location);
        glVertexAttribPointer(texcoord_location, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*) (2 * float.sizeof));

        FT_Face face;
        if (FT_New_Face(ft, path.ptr, 0, &face)) {
            error_frontend("Could not open font.");
        }

        FT_Set_Pixel_Sizes(face, 0, 18);

        for (char c = 'a'; c <= 'z'; c++) {
            load_char(face, c);
        }

        for (char c = 'A'; c <= 'Z'; c++) {
            load_char(face, c);
        }

        for (char c = '0'; c <= '9'; c++) {
            load_char(face, c);
        }

        load_char(face, ' ');
        load_char(face, '!');
        load_char(face, '"');
        load_char(face, '#');
        load_char(face, '$');
        load_char(face, '%');
        load_char(face, '&');
        load_char(face, '\'');
        load_char(face, '(');
        load_char(face, ')');
        load_char(face, '*');
        load_char(face, '+');
        load_char(face, ',');
        load_char(face, '-');
        load_char(face, '.');
        load_char(face, '/');
        load_char(face, '[');
        load_char(face, ']');

        FT_Done_Face(face);
    }

    void load_char(FT_Face face, char c) {
        glUseProgram(font_shader);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);

        if (FT_Load_Char(face, c, FT_LOAD_RENDER)) {
            error_frontend("Could not load glyph '%c'", c);
        }

        uint texture;
        glGenTextures(1, &texture);
        glBindTexture(GL_TEXTURE_2D, texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, face.glyph.bitmap.width, face.glyph.bitmap.rows, 0, GL_RED, GL_UNSIGNED_BYTE, face.glyph.bitmap.buffer);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

        characters[c] = Character(
            texture,
            face.glyph.advance.x,
            face.glyph.bitmap_left,
            face.glyph.bitmap_top,
            face.glyph.bitmap.width,
            face.glyph.bitmap.rows
        );

        log_frontend("character[%d] = %s", c, characters[c]);
    }

    RenderedTextHandle obtain_text_handle() {
        glUseProgram(font_shader);

        uint vao, vbo;
        glGenVertexArrays(1, &vao);
        glGenBuffers(1, &vbo);
        glBindVertexArray(vao);
        glBindBuffer(GL_ARRAY_BUFFER, vbo);

        return RenderedTextHandle(vao, vbo);
    }
    
    void set_string(RenderedTextHandle handle, Color color, string text, float x, float y, float w, float h) {
        int string_width = 0;
        int string_height = 0;

        foreach (char c; text) {
            Character character = characters[c];
            string_width += character.advance >> 6;
            string_height = max(string_height, character.size_y);
        }

        x = x + (w - string_width) / 2;
        y = y + (h - string_height) / 2;
    
        foreach (char c; text) {
            glUseProgram(font_shader);

            glActiveTexture(GL_TEXTURE0);
            glBindVertexArray(handle.vao);
            glBindBuffer(GL_ARRAY_BUFFER, handle.vbo);

            auto position_location = glGetAttribLocation(font_shader, "in_Position");
            glEnableVertexAttribArray(position_location);
            glVertexAttribPointer(position_location, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*) 0);
            
            auto texcoord_location = glGetAttribLocation(font_shader, "in_UV");
            glEnableVertexAttribArray(texcoord_location);
            glVertexAttribPointer(texcoord_location, 2, GL_FLOAT, GL_FALSE, 4 * float.sizeof, cast(void*) (2 * float.sizeof));
            
            glUniform4fv(1, 1, cast(float*) &color);

            Character character = characters[c];

            float xpos = x + character.bearing_x;
            float ypos = y - (character.size_y - character.bearing_y);
            float width = character.size_x;
            float height = character.size_y;
            log_frontend("xpos: %f, ypos: %f, width: %f, height: %f", xpos, ypos, width, height);

            float[] buffer_data = [
                xpos,         ypos + height, 0.0f, 0.0f,            
                xpos,         ypos,          0.0f, 1.0f,
                xpos + width, ypos,          1.0f, 1.0f,
                xpos + width, ypos + height, 1.0f, 0.0f           
            ];

            x += character.advance >> 6;
    
            glBindTexture(GL_TEXTURE_2D, character.texture);
            glBindBuffer(GL_ARRAY_BUFFER, handle.vbo);
            glBufferData(GL_ARRAY_BUFFER, buffer_data.length * float.sizeof, buffer_data.ptr, GL_STATIC_DRAW);
            glBindBuffer(GL_ARRAY_BUFFER, 0);   
            glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
        }
    }
}