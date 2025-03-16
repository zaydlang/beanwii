module ui.sdl.window;

import bindbc.sdl;

interface Window {
    void handle_event(SDL_Event event);
    void draw();
}