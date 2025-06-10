module ui.sdl.device;

import bindbc.freetype;
import bindbc.opengl;
import bindbc.sdl;
import emu.hw.hollywood.hollywood;
import emu.hw.ipc.usb.wiimote;
import emu.hw.wii;
import std.algorithm;
import std.array;
import std.file;
import std.format;
import std.string;
import ui.device;
import ui.sdl.button;
import ui.sdl.color;
import ui.sdl.font;
import ui.sdl.hollywood.texturewidget;
import ui.sdl.rect;
import ui.sdl.scroll;
import ui.sdl.shaders.shader;
import ui.sdl.tab;
import ui.sdl.widget;
import ui.sdl.window;
import util.bitop;
import util.log;
import util.number;

class SdlDevice : MultiMediaDevice, Window {
    SDL_Window* window;
    SDL_Color* frame_buffer;
    SDL_Renderer* renderer;
    SDL_GLContext gl_context;

    bool debugging;

    Widget[] widgets;
    Scroll tri_viewer;

    Wii wii;
    Hollywood hollywood;

    enum SCREEN_BORDER_WIDTH    = 10;
    enum DEBUGGER_PANEL_WIDTH   = 250;
    enum DEBUGGER_PANEL_HEIGHT  = WII_SCREEN_HEIGHT;
    enum DEBUGGER_SCREEN_WIDTH  = WII_SCREEN_WIDTH  + SCREEN_BORDER_WIDTH * 3 + DEBUGGER_PANEL_WIDTH;
    enum DEBUGGER_SCREEN_HEIGHT = WII_SCREEN_HEIGHT + SCREEN_BORDER_WIDTH * 2;

    long mouse_wheel;

    GLint widget_shader;
    GLint font_shader;
    GLint debug_tri_shader;
    Font font_spm_small;
    Font font_spm_medium;

    bool paused;
    bool running;

    int hovered_shape = -1;

    ShapeGroup[] drawn_shape_groups;
    DebugTriWindow[] debug_tri_windows;

    Window active_window;
    Window[SDL_Window*] window_map;

    float[16] projection_matrix;

    SdlButton pause_button;

    this(Wii wii, int screen_scale, bool start_debugger) {
        this.wii = wii;
        
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

        gl_context = SDL_GL_CreateContext(window);
        
        if (!gl_context) {
            error_frontend("SDL_GL_CreateContext returned an error: %s\n", SDL_GetError());
        }

        // SDL_GL_SetSwapInterval(1);
        // SDL_SetHint(SDL_HINT_RENDER_VSYNC, "0");

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
            GLint debug_tri_shader = load_shader("source/ui/sdl/shaders/debug_tri");

            this.widget_shader = widget_shader;
            this.font_shader = font_shader;
            this.debug_tri_shader = debug_tri_shader;

            this.font_spm_small  = new Font("source/ui/sdl/font/SuperMarioScript2Demo-Regular.ttf", ft, font_shader, 18);
            this.font_spm_medium = new Font("source/ui/sdl/font/SuperMarioScript2Demo-Regular.ttf", ft, font_shader, 26);

            auto button_width = (DEBUGGER_PANEL_WIDTH - SCREEN_BORDER_WIDTH) / 2;
            pause_button = new SdlButton(WII_SCREEN_WIDTH + SCREEN_BORDER_WIDTH * 2, SCREEN_BORDER_WIDTH + DEBUGGER_PANEL_HEIGHT - 50, button_width, 50, from_hex(0xCAF0F8), from_hex(0x444444), font_spm_medium, "Pause", widget_shader,
                (void* _) { paused = !paused; pause_button.text = paused ? "Resume" : "Pause"; }, (void* _) {}, (void* _) {}, null);
            widgets ~= pause_button;
            auto exit = new SdlButton(WII_SCREEN_WIDTH + SCREEN_BORDER_WIDTH * 3 + button_width, SCREEN_BORDER_WIDTH + DEBUGGER_PANEL_HEIGHT - 50, button_width, 50, from_hex(0xef9688), from_hex(0x444444), font_spm_medium, "Exit", widget_shader,
                (void* _) { running = false; }, (void* _) {}, (void* _) {}, null);
            widgets ~= exit;
            auto reload = new SdlButton(WII_SCREEN_WIDTH + SCREEN_BORDER_WIDTH * 2, 60, DEBUGGER_PANEL_WIDTH, 50, from_hex(0xCAF0F8), from_hex(0x444444), font_spm_medium, "Reload Shaders", widget_shader,
                (void* _) { hollywood.debug_reload_shaders(); }, (void* _) {}, (void* _) {}, null);
            widgets ~= reload;
            auto dump_memory = new SdlButton(WII_SCREEN_WIDTH + SCREEN_BORDER_WIDTH * 2, 120, DEBUGGER_PANEL_WIDTH, 50, from_hex(0xCAF0F8), from_hex(0x444444), font_spm_medium, "Dump Memory", widget_shader,
                (void* _) { wii.debug_dump_memory(); }, (void* _) {}, (void* _) {}, null);
            widgets ~= dump_memory;

            tri_viewer = new Scroll(WII_SCREEN_WIDTH + SCREEN_BORDER_WIDTH * 2, SCREEN_BORDER_WIDTH + DEBUGGER_PANEL_HEIGHT - 360, DEBUGGER_PANEL_WIDTH, 300, from_hex(0xCAF0F8), widget_shader, from_hex(0x444444), font_spm_medium, "Triangles");
            tri_viewer.set_items([]);

            widgets ~= tri_viewer;

            projection_matrix = [
                2.0 / DEBUGGER_SCREEN_WIDTH, 0, 0, 0,
                0, 2.0 / DEBUGGER_SCREEN_HEIGHT, 0, 0,
                0, 0, 0, 0,
                -1, -1, 0, 1
            ];

            glUseProgram(widget_shader);
            glUniformMatrix4fv(glGetUniformLocation(widget_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);
            glUseProgram(font_shader);
            glUniformMatrix4fv(glGetUniformLocation(font_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);

            this.hollywood = wii.debug_get_hollywood();
            this.paused = false;
            debug_tri_windows = [];

            active_window = cast(Window) this;
            window_map[window] = cast(Window) this;
        }

        running = true;
    }
    
    override {
        void handle_event(SDL_Event event) {
            long new_mouse_wheel = mouse_wheel;
        
            switch (event.type) {
                case SDL_MOUSEWHEEL:
                    new_mouse_wheel = event.wheel.y;
                    break;
                
                default:
                    break;
            }
                
            long mouse_wheel_delta = new_mouse_wheel - mouse_wheel;

            int mouse_x, mouse_y;
            int mouse_state = SDL_GetMouseState(&mouse_x, &mouse_y);
            mouse_y = DEBUGGER_SCREEN_HEIGHT - mouse_y;

            foreach (Widget widget; widgets) {
                widget.update(mouse_x, mouse_y, mouse_state, mouse_wheel_delta);
            }
        }

        void update() {
            SDL_PumpEvents();
            handle_input();

            if (debugging) {
                SDL_Event event;
                while(SDL_PollEvent(&event)) {
                    switch (event.type) {
                        case SDL_WINDOWEVENT:
                            switch (event.window.event) {
                                case SDL_WINDOWEVENT_ENTER:
                                    active_window = window_map[SDL_GetWindowFromID(event.window.windowID)];
                                    break;
                                
                                default:
                                    active_window.handle_event(event);
                                    break;
                            }
                            break;

                        default:
                            active_window.handle_event(event);
                            break;
                    }
                }
            }
        }

        int x = 0;
        void draw() {
            SDL_GL_MakeCurrent(window, gl_context);
            glUseProgram(widget_shader);
            glUniformMatrix4fv(glGetUniformLocation(widget_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);
            glUseProgram(font_shader);
            glUniformMatrix4fv(glGetUniformLocation(font_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);

            if (debugging) {
                if (!paused) {
                    Widget[] items;
                    drawn_shape_groups = hollywood.debug_get_drawn_shape_groups();
                    
                    for (int i = 0; i < drawn_shape_groups.length; i++) {
                        auto tri = new SdlButton(0, 0, DEBUGGER_PANEL_WIDTH, 30, from_hex(0x90e0ef), from_hex(0x0077b6), font_spm_medium, "Group #%d".format(i), widget_shader,
                            (void* idx) { create_debug_tri_window(this, cast(int) idx); }, (void* idx) { hovered_shape = cast(int) idx; }, (void* idx) { if (hovered_shape == cast(int) idx) hovered_shape = -1; }, cast(void*) i);
                        items ~= tri;
                    }

                    tri_viewer.set_items(items);
                }

                glDisable(GL_SCISSOR_TEST);

                glViewport(0, 0, DEBUGGER_SCREEN_WIDTH, DEBUGGER_SCREEN_HEIGHT);
    
                glEnable(GL_DEPTH_TEST);
                glDepthFunc(GL_ALWAYS);
                glEnable(GL_BLEND);
                glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

                foreach (Widget widget; widgets) {
                    widget.draw();
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
                
                if (paused) {
                    hollywood.debug_redraw(drawn_shape_groups);

                    if (hovered_shape != -1) {
                        log_frontend("hovered_shape: %d", hovered_shape);
                        glUseProgram(debug_tri_shader);
                        hollywood.debug_draw_shape_group(drawn_shape_groups[hovered_shape]);
                    }
                }

                foreach (DebugTriWindow window; debug_tri_windows) {
                    window.draw();
                }
                
                SDL_GL_MakeCurrent(window, gl_context);
                glUseProgram(widget_shader);
                glUniformMatrix4fv(glGetUniformLocation(widget_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);
                glUseProgram(font_shader);
                glUniformMatrix4fv(glGetUniformLocation(font_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);

                glEnable(GL_SCISSOR_TEST);
                glViewport(SCREEN_BORDER_WIDTH, SCREEN_BORDER_WIDTH, 
                    WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT);
                glScissor(SCREEN_BORDER_WIDTH, SCREEN_BORDER_WIDTH, WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT);
            } else {
                SDL_GL_SwapWindow(window);
            }

        }

        void update_rom_title(string title) {

        }

        void present_videobuffer(VideoBuffer* buffer) {
        }
   
        void set_fps(int fps) {
            SDL_SetWindowTitle(window, cast(const char*) format("%d FPS", fps));
        }

        void update_icon(Pixel[32][32] texture) {

        }

        void push_sample(Sample s) {

        }

        void handle_input() {
            enum KeyMapping = [
                WiimoteButton.A : SDL_SCANCODE_A,
                WiimoteButton.B : SDL_SCANCODE_B,
                WiimoteButton.Plus : SDL_SCANCODE_P,
                WiimoteButton.Minus : SDL_SCANCODE_L,
                WiimoteButton.Home : SDL_SCANCODE_H,
                WiimoteButton.One : SDL_SCANCODE_1,
                WiimoteButton.Two : SDL_SCANCODE_2,
                WiimoteButton.Up : SDL_SCANCODE_UP,
                WiimoteButton.Down : SDL_SCANCODE_DOWN,
                WiimoteButton.Left : SDL_SCANCODE_LEFT,
                WiimoteButton.Right : SDL_SCANCODE_RIGHT,
            ];

            foreach (wiimote_key, host_key; KeyMapping) {
                u8* keyboard_state = SDL_GetKeyboardState(null);
                wii.set_wiimote_button(wiimote_key, keyboard_state[host_key] != 0);
            }
        }

        bool should_fast_forward() {
            return false;
        }

        bool should_exit() {
            return !running;
        }

        bool is_running() {
            return !paused;
        }
    }

    void on_window_close(DebugTriWindow window) {
        debug_tri_windows = debug_tri_windows.filter!(w => w !is window).array;
    }

    void create_debug_tri_window(SdlDevice parent, int shape_index) {
        auto window = new DebugTriWindow(parent, shape_index);
        debug_tri_windows ~= window;
        window_map[window.window] = window;
    }
}

final class DebugTriWindow : Window {
    enum DEBUG_TRI_WINDOW_WIDTH = 800;
    enum DEBUG_TRI_WINDOW_HEIGHT = 500;

    SdlDevice parent;

    SDL_Window* window;
    SDL_Renderer* renderer;
    SDL_GLContext gl_context;

    Widget[] widgets;

    ShapeGroup debug_shape;

    RenderedTextHandle tev_stage_title_handle;
    RenderedTextHandle[16] tev_stage_color_text_handles;
    RenderedTextHandle[16] tev_stage_alfa_text_handles;
    RenderedTextHandle[8]  tex_info_text_handles;

    this(SdlDevice parent, int shape_index) {
        this.parent = parent;
        this.debug_shape = parent.drawn_shape_groups[shape_index];

        SDL_GL_SetAttribute(SDL_GL_SHARE_WITH_CURRENT_CONTEXT, 1);
        window = SDL_CreateWindow("debug tri", 
            SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 
            DEBUG_TRI_WINDOW_WIDTH, DEBUG_TRI_WINDOW_HEIGHT, SDL_WINDOW_SHOWN);
    
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

        gl_context = SDL_GL_CreateContext(window);
        
        if (!gl_context) {
            error_frontend("SDL_GL_CreateContext returned an error: %s\n", SDL_GetError());
        }

        SDL_GL_MakeCurrent(window, gl_context);
        // auto exit_button = new SdlButton(0, 0, DEBUG_TRI_WINDOW_WIDTH, 100, from_hex(0xef9688), from_hex(0x444444), parent.font_spm_medium, "Close", parent.widget_shader,
            // (void* _) { SDL_PumpEvents(); SDL_GL_DeleteContext(gl_context); SDL_DestroyRenderer(renderer); SDL_DestroyWindow(window); parent.on_window_close(this); }, (void* _) {}, (void* _) {}, null);
        // widgets ~= exit_button;

        for (int i = 0; i < debug_shape.tev_config.num_tev_stages; i++) {
            tev_stage_color_text_handles[i] = parent.font_spm_small.obtain_text_handle();
            tev_stage_alfa_text_handles[i] = parent.font_spm_small.obtain_text_handle();
        }

        for (int i = 0; i < 8; i++) {
            tex_info_text_handles[i] = parent.font_spm_small.obtain_text_handle();
        }

        tev_stage_title_handle = parent.font_spm_medium.obtain_text_handle();

        TextureWidget[8] texture_widgets = new TextureWidget[8];
        
        GLint debug_texture_shader = load_shader("source/ui/sdl/shaders/debug_texture");
        texture_widgets = [
            new TextureWidget(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, parent.hollywood, parent.widget_shader, debug_texture_shader, from_hex(0x0077b6), debug_shape.texture[0], parent.font_spm_small),
            new TextureWidget(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, parent.hollywood, parent.widget_shader, debug_texture_shader, from_hex(0x0077b6), debug_shape.texture[1], parent.font_spm_small),
            new TextureWidget(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, parent.hollywood, parent.widget_shader, debug_texture_shader, from_hex(0x0077b6), debug_shape.texture[2], parent.font_spm_small),
            new TextureWidget(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, parent.hollywood, parent.widget_shader, debug_texture_shader, from_hex(0x0077b6), debug_shape.texture[3], parent.font_spm_small),
            new TextureWidget(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, parent.hollywood, parent.widget_shader, debug_texture_shader, from_hex(0x0077b6), debug_shape.texture[4], parent.font_spm_small),
            new TextureWidget(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, parent.hollywood, parent.widget_shader, debug_texture_shader, from_hex(0x0077b6), debug_shape.texture[5], parent.font_spm_small),
            new TextureWidget(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, parent.hollywood, parent.widget_shader, debug_texture_shader, from_hex(0x0077b6), debug_shape.texture[6], parent.font_spm_small),
            new TextureWidget(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, parent.hollywood, parent.widget_shader, debug_texture_shader, from_hex(0x0077b6), debug_shape.texture[7], parent.font_spm_small),
        ];

        Rect[8] texture_rects = new Rect[8];
        texture_rects = [
            new Rect(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, Color(0), parent.widget_shader),
            new Rect(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, Color(0), parent.widget_shader),
            new Rect(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, Color(0), parent.widget_shader),
            new Rect(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, Color(0), parent.widget_shader),
            new Rect(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, Color(0), parent.widget_shader),
            new Rect(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, Color(0), parent.widget_shader),
            new Rect(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, Color(0), parent.widget_shader),
            new Rect(50, 20, DEBUG_TRI_WINDOW_WIDTH - 70, DEBUG_TRI_WINDOW_HEIGHT - 40, Color(0), parent.widget_shader),
        ];

        // widgets ~= new Rect(10, 300, DEBUG_TRI_WINDOW_WIDTH - 20, DEBUG_TRI_WINDOW_HEIGHT - 310, from_hex(0x90e0ef), parent.widget_shader);    
        widgets ~= new TabManager(10, 10, DEBUG_TRI_WINDOW_WIDTH - 20, DEBUG_TRI_WINDOW_HEIGHT - 20, 
            cast(Widget[]) texture_widgets, from_hex(0x90e0ef), parent.font_spm_small, parent.widget_shader);
    }

    string generate_optimized_tev_equation(string dest, float scale, float bias, string a, string b, string c, string d) {
        string equation;

        // equation = (d + ((1 - c) * a + c * b) + bias) * scale
        // equation = d + ...
        
        if (scale == 0) {
            return "0";
        }

        if (d != "0") {
            equation = d;
        } else {
            equation = "";
        }

        // equation += (1 - c) * a + ...
        if (a == "0" || c == "1") {
            // do nothing
        } else if (a == "1") {
            if (equation != "") equation ~= " + ";
            equation ~= "(1 - " ~ c ~ ")";
        } else if (c == "0") {
            if (equation != "") equation ~= " + ";
            equation ~= a;
        } else {
            if (equation != "") equation ~= " + ";
            equation ~= "(1 - " ~ c ~ ") * " ~ a;
        }
    
        // equation += c * b + ...
        if (b == "0" || c == "0") {
            // do nothing
        } else if (b == "1") {
            if (equation != "") equation ~= " + ";
            equation ~= c;
        } else if (c == "1") {
            if (equation != "") equation ~= " + ";
            equation ~= b;
        } else {
            if (equation != "") equation ~= " + ";
            equation ~= c ~ " * " ~ b;
        }

        // equation *= scale
        if (bias != 0) {
            equation = "(" ~ equation ~ " + %.1f)".format(bias);
        }
        
        if (scale != 1) {
            equation = "(" ~ equation ~ ") * %.1f".format(scale);
        }
        
        return "%s = %s".format(dest, equation);
    }

    string calculate_color_tev_stage_text(int stage) {
        string a = calculate_color_input_text(debug_shape.tev_config.stages[stage].in_color_a);
        string b = calculate_color_input_text(debug_shape.tev_config.stages[stage].in_color_b);
        string c = calculate_color_input_text(debug_shape.tev_config.stages[stage].in_color_c);
        string d = calculate_color_input_text(debug_shape.tev_config.stages[stage].in_color_d);
        float bias_val = debug_shape.tev_config.stages[stage].bias_color;
        float scale_val = debug_shape.tev_config.stages[stage].scale_color;
        int dest = debug_shape.tev_config.stages[stage].color_dest;

        return generate_optimized_tev_equation(
            "r%d".format(dest), 
            scale_val, 
            bias_val, 
            a, b, c, d
        );


        // d + (1 - c) * a + c * b;

        // string equation;
        
        // // equation = d + ...
        // if (d != "0") {
        //     equation ~= d;
        // }

        // // equation += (1 - c) * a + ...
        // if (a == "0" || c == "1") {
        //     // do nothing
        // } else if (a == "1") {
        //     equation ~= " + (1 - " ~ c ~ ")";
        // } else if (c == "0") {
        //     equation ~= " + " ~ a;
        // } else {
        //     equation ~= " + (1 - " ~ c ~ ") * " ~ a;
        // }
    
        // // equation += c * b + ...
        // if (b == "0" || c == "0") {
        //     // do nothing
        // } else if (b == "1") {
        //     equation ~= " + " ~ c;
        // } else if (c == "1") {
        //     equation ~= " + " ~ b;
        // } else {
        //     equation ~= " + " ~ c ~ " * " ~ b;
        // }
        
        // return "r%d = %s".format(dest, equation);
    }

    string calculate_alfa_tev_stage_text(int stage) {
        string a = calculate_alfa_input_text(debug_shape.tev_config.stages[stage].in_alfa_a);
        string b = calculate_alfa_input_text(debug_shape.tev_config.stages[stage].in_alfa_b);
        string c = calculate_alfa_input_text(debug_shape.tev_config.stages[stage].in_alfa_c);
        string d = calculate_alfa_input_text(debug_shape.tev_config.stages[stage].in_alfa_d);
        float bias_val = debug_shape.tev_config.stages[stage].bias_alfa;
        float scale_val = debug_shape.tev_config.stages[stage].scale_alfa;
        int dest = debug_shape.tev_config.stages[stage].alfa_dest;

        return generate_optimized_tev_equation(
            "a%d".format(dest), 
            scale_val, 
            bias_val, 
            a, b, c, d
        );
    }

    string calculate_color_input_text(int color_input) {
        final switch (color_input) {
            case 0:  return "r0";
            case 1:  return "a0";
            case 2:  return "r1";
            case 3:  return "a1";
            case 4:  return "r2";
            case 5:  return "a2";
            case 6:  return "r3";
            case 7:  return "a3";
            case 8:  return "tx";
            case 9:  return "ta";
            case 10: return "ras";
            case 11: return "ras.a";
            case 12: return "1";
            case 13: return "0.5";
            case 14: return "k";
            case 15: return "0";
        }
    }

    string calculate_alfa_input_text(int alfa_input) {
        final switch (alfa_input) {
            case 0: return "a0";
            case 1: return "a1";
            case 2: return "a2";
            case 3: return "a3";
            case 4: return "ta";
            case 5: return "ras.a";
            case 6: return "1";
            case 7: return "0";
        }
    }

    void draw() {
        SDL_GL_MakeCurrent(window, gl_context);

        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_ALWAYS);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        
        static const float[16] projection_matrix = [
            2.0 / DEBUG_TRI_WINDOW_WIDTH, 0, 0, 0,
            0, 2.0 / DEBUG_TRI_WINDOW_HEIGHT, 0, 0,
            0, 0, 0, 0,
            -1, -1, 0, 1
        ];

        glUseProgram(parent.widget_shader);
        glUniformMatrix4fv(glGetUniformLocation(parent.widget_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);
        glUseProgram(parent.font_shader);
        glUniformMatrix4fv(glGetUniformLocation(parent.font_shader, "MVP"), 1, GL_FALSE, projection_matrix.ptr);
        glViewport(0, 0, DEBUG_TRI_WINDOW_WIDTH, DEBUG_TRI_WINDOW_HEIGHT);

        Color clear_color = from_hex(0x0077b6);
        glClearColor(clear_color.r, clear_color.g, clear_color.b, clear_color.a);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
        glDisable(GL_DEPTH_TEST);

        foreach (Widget widget; widgets) {
            widget.draw();
        }

        // for (int i = 0; i < debug_shape.tev_config.num_tev_stages; i++) {
        //     parent.font_spm_small.set_string(
        //         tev_stage_color_text_handles[i], from_hex(0x444444), Justify.Left,
        //         calculate_color_tev_stage_text(i), 
        //         20, DEBUG_TRI_WINDOW_HEIGHT - 30 * (i + 2), DEBUG_TRI_WINDOW_WIDTH, 30
        //     );

        //     parent.font_spm_small.set_string(
        //         tev_stage_alfa_text_handles[i], from_hex(0x444444), Justify.Left,
        //         calculate_alfa_tev_stage_text(i), 
        //         10 + DEBUG_TRI_WINDOW_WIDTH / 2, DEBUG_TRI_WINDOW_HEIGHT - 30 * (i + 2), DEBUG_TRI_WINDOW_WIDTH, 30
        //     );
        // }

        // parent.font_spm_medium.set_string(
            // tev_stage_title_handle, from_hex(0x444444), Justify.Center,
            // "TEV Stages", 
            // 20, DEBUG_TRI_WINDOW_HEIGHT - 40, DEBUG_TRI_WINDOW_WIDTH, 30
        // );

        for (int i = 0; i < 8; i++) {
            // if (!debug_shape.enabled_textures_bitmap.bit(i)) {
            //     continue;
            // }

            // parent.font_spm_small.set_string(
            //     tex_info_text_handles[i], from_hex(0x444444), Justify.Left,
            //     "Texture %d: Address: %08x, Format: %s".format(
            //         i, debug_shape.texture_address[i], debug_shape.texture_format[i]
            //     ),
            // );
        }

        SDL_GL_SwapWindow(window);
    }

    override void handle_event(SDL_Event event) {
        SDL_PumpEvents();

        int mouse_x, mouse_y;
        int mouse_state = SDL_GetMouseState(&mouse_x, &mouse_y);
        mouse_y = DEBUG_TRI_WINDOW_HEIGHT - mouse_y;

        long mouse_wheel = 0;

        switch (event.type) {
            case SDL_MOUSEWHEEL:
                mouse_wheel = event.wheel.y;
                break;

            default:
                break;
        }

        foreach (Widget widget; widgets) {
            widget.update(mouse_x, mouse_y, mouse_state, mouse_wheel);
        }
    }
}