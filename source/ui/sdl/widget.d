module ui.sdl.widget;

abstract class Widget {
    protected int x;
    protected int y;
    protected int w;
    protected int h;
    
    this(int x, int y, int w, int h) {
        this.x = x;
        this.y = y;
        this.w = w;
        this.h = h;
    }

    void set_x(int x) {
        this.x = x;
    }

    void set_y(int y) {
        this.y = y;
    }

    void set_w(int w) {
        this.w = w;
    }

    void set_h(int h) {
        this.h = h;
    }

    int get_x() {
        return x;
    }

    int get_y() {
        return y;
    }

    int get_w() {
        return w;
    }

    int get_h() {
        return h;
    }

    void draw() {
    }

    void update(int mouse_x, int mouse_y, int mouse_state, long mouse_wheel) {
    }
}