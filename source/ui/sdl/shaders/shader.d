module ui.sdl.shaders.shader;

import bindbc.opengl;
import std.file;
import util.log;

static GLint load_shader(string path) {
    string vertex_path = path ~ "/vertex.glsl";
    string fragment_path = path ~ "/fragment.glsl";

    auto vertex_shader   = glCreateShader(GL_VERTEX_SHADER);
    auto fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);	

    string vertex_text   = readText(vertex_path);
    string fragment_text = readText(fragment_path);
    GLint vertex_text_length = cast(GLint) vertex_text.length;
    GLint fragment_text_length = cast(GLint) fragment_text.length;

    auto vertex_text_const_char  = cast(const char*) vertex_text.ptr;
    auto fragment_text_const_char = cast(const char*) fragment_text.ptr;
    glShaderSource(vertex_shader,   1, &vertex_text_const_char,   &vertex_text_length);
    glShaderSource(fragment_shader, 1, &fragment_text_const_char, &fragment_text_length);
    
    GLint compiled;

    glCompileShader(vertex_shader);
    glGetShaderiv(vertex_shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        error_frontend("Vertex shader compilation error.");
    } 

    glCompileShader(fragment_shader);
    glGetShaderiv(fragment_shader, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        import core.stdc.stdlib;
        import std.string;
        
        char* info_log = cast(char*) malloc(10000000);
        int info_log_length;

        glGetShaderInfoLog(fragment_shader, 10000000, &info_log_length, cast(char*) info_log);
        error_frontend("Fragment shader compilation error: %s", info_log.fromStringz);
    } 
    
    GLint gl_program = glCreateProgram();

    glBindAttribLocation(gl_program, 0, "in_Position");
        
    glAttachShader(gl_program, vertex_shader);
    glAttachShader(gl_program, fragment_shader);
    
    glLinkProgram(gl_program);

    return gl_program;
}