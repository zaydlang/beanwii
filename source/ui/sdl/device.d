module ui.sdl.device;

import bindbc.opengl;
import bindbc.sdl;
import emu.hw.wii;
import std.format;
import std.string;
import ui.device;
import ui.reng.rengcore;
import ui.reng.wiivideo;
import util.log;
import util.number;

// two vertex array objects, one for each object drawn
uint[2] vertexArrayObjID;
// three vertex buffer objects in this example
uint[3] vertexBufferObjID;

// Globals
// Real programs don't use globals :-D
// Data would normally be read from files
GLfloat[9] vertices = [-416.0f,228.0f,0.0f,
						-416.0f,-228.0f,0.0f,
                    416.0f,228.0f,0.0f ];
GLfloat[9] colours = [	1.0f, 0.0f, 0.0f,
						0.0f, 1.0f, 0.0f,
						0.0f, 0.0f, 1.0f ];
GLfloat[9] vertices2 = [416.0f,-228.0f,0.0f,
						-416.0f,-228.0f,0.0f,
                    416.0f,228.0f,0.0f ];
	GLuint p, f, v;
                
class SdlDevice : MultiMediaDevice {
    SDL_Window* window;
    SDL_Color* frame_buffer;

    this(int screen_scale, bool start_debugger) {
        loadSDL();

        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);

        if (start_debugger) {
            error_frontend("SDL device does not support debugger");
        }

        if (SDL_Init(SDL_INIT_VIDEO) < 0) {
            error_frontend("SDL_Init returned an error: %s\n", SDL_GetError());
        }

        window = SDL_CreateWindow("beanwii", 
            SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, 
            WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT, SDL_WINDOW_SHOWN);

        if (!window) {
            error_frontend("SDL_CreateWindow returned an error: %s\n", SDL_GetError());
        }
        
        SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, 0);

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

        // Would load objects from file here - but using globals in this example	
        // Allocate Vertex Array Objects
        glGenVertexArrays(2, vertexArrayObjID.ptr);
        // Setup first Vertex Array Object
        glBindVertexArray(vertexArrayObjID[0]);
        glGenBuffers(2, vertexBufferObjID.ptr);
        
        // VBO for vertex data
        glBindBuffer(GL_ARRAY_BUFFER, vertexBufferObjID[0]);
        glBufferData(GL_ARRAY_BUFFER, 9 * GLfloat.sizeof, vertices.ptr, GL_STATIC_DRAW);
        glVertexAttribPointer(cast(GLuint)0, 3, GL_FLOAT, GL_FALSE, 0, null); 
        glEnableVertexAttribArray(0);

        // VBO for colour data
        glBindBuffer(GL_ARRAY_BUFFER, vertexBufferObjID[1]);
        glBufferData(GL_ARRAY_BUFFER, 9 * GLfloat.sizeof, colours.ptr, GL_STATIC_DRAW);
        glVertexAttribPointer(cast(GLuint)1, 3, GL_FLOAT, GL_FALSE, 0, null);
        glEnableVertexAttribArray(1);

        // Setup second Vertex Array Object
        glBindVertexArray(vertexArrayObjID[1]);
        glGenBuffers(1, &vertexBufferObjID[2]);

        // VBO for vertex data
        glBindBuffer(GL_ARRAY_BUFFER, vertexBufferObjID[2]);
        glBufferData(GL_ARRAY_BUFFER, 9 * GLfloat.sizeof, vertices2.ptr, GL_STATIC_DRAW);
        glVertexAttribPointer(cast(GLuint)0, 3, GL_FLOAT, GL_FALSE, 0, null); 
        glEnableVertexAttribArray(0);

        glBindVertexArray(0);

    // // Create one OpenGL texture
    // glGenTextures(1, &textureID);

    // // "Bind" the newly created texture : all future texture functions will modify this texture
    // glBindTexture(GL_TEXTURE_2D, textureID);

    // // Give the image to OpenGL
    // glTexImage2D(GL_TEXTURE_2D, 0,GL_RGB, 456, 832, 0, GL_BGR, GL_UNSIGNED_BYTE, sexture);

    // glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    // glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);


        glViewport(0, 0, WII_SCREEN_WIDTH, WII_SCREEN_HEIGHT);
    }
    
    override {
        void update() {
            // glUseProgram(p);
            // GLuint MatrixID = glGetUniformLocation(p, "MVP");
            // GLfloat[16] MVP = [
            //     0.0024038462434, 0, 0, 0,
            //     0, 0.0043859649, 0, 0,
            //     0, 0, 0, 0,
            //     0, 0, 0, 1
            // ];

            // glUniformMatrix4fv(MatrixID, 1, GL_TRUE, &(MVP[0]));

            // clear the screen
            // glClear(GL_COLOR_BUFFER_BIT);

            // glBindVertexArray(vertexArrayObjID[0]);	// First VAO
            // glDrawArrays(GL_TRIANGLES, 0, 3);	// draw first object
            // glBindVertexArray(vertexArrayObjID[1]);	// First VAO
            // glDrawArrays(GL_TRIANGLES, 0, 3);	// draw first object

            // glBindVertexArray(0);
        }

        void draw() {

        }

        void update_rom_title(string title) {

        }

        // video stuffs
        void present_videobuffer(VideoBuffer buffer) {
            // for (int y = 0; y < WII_SCREEN_HEIGHT; y++) {
            // for (int x = 0; x < WII_SCREEN_WIDTH;  x++) {
            //     frame_buffer[x + y * WII_SCREEN_WIDTH].r = cast(u8) buffer[x][y].r;
            //     frame_buffer[x + y * WII_SCREEN_WIDTH].g = cast(u8) buffer[x][y].g;
            //     frame_buffer[x + y * WII_SCREEN_WIDTH].b = cast(u8) buffer[x][y].b;
            //     frame_buffer[x + y * WII_SCREEN_WIDTH].a = 0xFF;
            // }
            // }

            // SDL_UpdateWindowSurface(window);
            SDL_GL_SwapWindow(window);
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