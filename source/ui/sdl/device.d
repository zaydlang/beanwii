module ui.sdl.device;

import bindbc.freetype;
import bindbc.opengl;
import bindbc.sdl;
import emu.hw.wii;
import std.file;
import std.format;
import std.string;
import ui.device;
import ui.sdl.button;
import ui.sdl.color;
import ui.sdl.drawable;
import ui.sdl.font;
import ui.sdl.shaders.shader;
import ui.sdl.updatable;
import util.log;
import util.number;
                
class SdlDevice : MultiMediaDevice {
    SDL_Window* window;
    SDL_Color* frame_buffer;
    SDL_Renderer* renderer;

    bool debugging;

    Drawable[] drawables;
    Updatable[] updatables;

    enum SCREEN_BORDER_WIDTH    = 10;
    enum DEBUGGER_PANEL_WIDTH   = 250;
    enum DEBUGGER_PANEL_HEIGHT  = WII_SCREEN_HEIGHT;
    enum DEBUGGER_SCREEN_WIDTH  = WII_SCREEN_WIDTH  + SCREEN_BORDER_WIDTH * 3 + DEBUGGER_PANEL_WIDTH;
    enum DEBUGGER_SCREEN_HEIGHT = WII_SCREEN_HEIGHT + SCREEN_BORDER_WIDTH * 2;

    this(int screen_scale, bool start_debugger) {
        loadSDL();

        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);

        if (SDL_Init(SDL_INIT_VIDEO) < 0) {
            error_frontend("SDL_Init returned an error: %s\n", SDL_GetError());
        }

        if (start_debugger) {
            window = SDL_CreateWindow("beanwii", 
                SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 
                DEBUGGER_SCREEN_WIDTH, DEBUGGER_SCREEN_HEIGHT, SDL_WINDOW_SHOWN);
        } else {
            window = SDL_CreateWindow("beanwii", 
            SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 
            WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT, SDL_WINDOW_SHOWN);
        }
    
        if (!window) {
            error_frontend("SDL_CreateWindow returned an error: %s\n", SDL_GetError());
        }
        
        renderer = SDL_CreateRenderer(window, -1, 0);

        if (!renderer) {
            error_frontend("SDL_CreateRenderer returned an error: %s\n", SDL_GetError());
        }

        SDL_Surface* screen = SDL_GetWindowSurface(window);
        
        if (!screen) {
            error_frontend("SDL_GetWindowSurface returned an error: %s\n", SDL_GetError());
        }

        frame_buffer = cast(SDL_Color*) screen.pixels;

        SDL_GLContext gl_context = SDL_GL_CreateContext(window);
        
        if (!gl_context) {
            error_frontend("SDL_GL_CreateContext returned an error: %s\n", SDL_GetError());
        }

        loadOpenGL();

        glViewport(0, 0, WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT);

        debugging = start_debugger;
        if (debugging) {
            loadFreeType();

            FT_Library ft;
            if (FT_Init_FreeType(&ft)) {
                error_frontend("Could not init freetype library.");
            }

            int major, minor, patch;
            FT_Library_Version(ft, &major, &minor, &patch);
            log_frontend("FT_Library_Version: %d.%d.%d", major, minor, patch);

            GLint widget_shader = load_shader("source/ui/sdl/shaders/widget");
            GLint font_shader   = load_shader("source/ui/sdl/shaders/font");
            
            auto font_code_squared = new Font("source/ui/sdl/font/code_squared.ttf", ft, font_shader);

            auto button = new SdlButton(0, DEBUGGER_PANEL_HEIGHT - 100, DEBUGGER_PANEL_WIDTH, 100, from_hex(0xCAF0F8), from_hex(0x0077b6), font_code_squared, "test", widget_shader);
            drawables ~= button;
            updatables ~= button;

            float[16] projection_matrix = [
                2.0 / DEBUGGER_PANEL_WIDTH, 0, 0, 0,
                0, 2.0 / DEBUGGER_PANEL_HEIGHT, 0, 0,
                0, 0, 0, 0,
                -1, -1, 0, 1
            ];

            glUseProgram(widget_shader);
            glUniformMatrix4fv(glGetUniformLocation(widget_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);
            glUseProgram(font_shader);
            glUniformMatrix4fv(glGetUniformLocation(font_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);
        }
    }
    
    override {
        void update() {
            if (debugging) {
                SDL_PumpEvents();

                int mouse_x, mouse_y;
                int mouse_state = SDL_GetMouseState(&mouse_x, &mouse_y);
                mouse_x -= SCREEN_BORDER_WIDTH * 2 + WII_SCREEN_WIDTH;
                mouse_y -= SCREEN_BORDER_WIDTH;
                mouse_y = DEBUGGER_PANEL_HEIGHT - mouse_y;

                foreach (Updatable updatable; updatables) {
                    updatable.update(mouse_x, mouse_y, mouse_state);
                }
            }
        }

        void draw() {
        }

        void update_rom_title(string title) {

        }

        void present_videobuffer(VideoBuffer buffer) {
            if (debugging) {
                glDisable(GL_SCISSOR_TEST);

                glViewport(WII_SCREEN_WIDTH + SCREEN_BORDER_WIDTH * 2, SCREEN_BORDER_WIDTH, 
                    DEBUGGER_PANEL_WIDTH, DEBUGGER_PANEL_HEIGHT);
    
                glEnable(GL_DEPTH_TEST);
                glDepthFunc(GL_ALWAYS);
                glEnable(GL_BLEND);
                glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

                foreach (Drawable drawable; drawables) {
                    drawable.draw();
                }

                SDL_GL_SwapWindow(window);

                Color clear_color = from_hex(0x0077b6);
                glClearColor(clear_color.r, clear_color.g, clear_color.b, clear_color.a);

                glEnable(GL_SCISSOR_TEST);
                glScissor(0, 0, DEBUGGER_SCREEN_WIDTH, SCREEN_BORDER_WIDTH);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
                glScissor(0, 0, SCREEN_BORDER_WIDTH, DEBUGGER_SCREEN_HEIGHT);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
                glScissor(SCREEN_BORDER_WIDTH + WII_SCREEN_WIDTH, 0, SCREEN_BORDER_WIDTH * 2 + DEBUGGER_PANEL_WIDTH, DEBUGGER_SCREEN_HEIGHT);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
                glScissor(0, SCREEN_BORDER_WIDTH + WII_SCREEN_HEIGHT, DEBUGGER_SCREEN_WIDTH, SCREEN_BORDER_WIDTH);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

                glViewport(SCREEN_BORDER_WIDTH, SCREEN_BORDER_WIDTH, 
                    WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT);
                glScissor(SCREEN_BORDER_WIDTH, SCREEN_BORDER_WIDTH, WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT);
            } else {
                SDL_GL_SwapWindow(window);
            }
        }
   
        void set_fps(int fps) {
            SDL_SetWindowTitle(window, cast(const char*) format("%d FPS", fps));
        }

        void update_icon(Pixel[32][32] texture) {

        }

        void push_sample(Sample s) {

        }

        void handle_input() {

        }

        bool should_fast_forward() {
            return false;
        }

        bool should_exit() {
            return SDL_QuitRequested();
        }
    }
}