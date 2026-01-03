#define WIIUSE_BLUEZ
#include <wiiuse.h>

// Simple accessor functions for wiimote_t fields
// This ensures we get the correct field offsets

int get_wiimote_unid(struct wiimote_t* wm) {
    return wm->unid;
}

int get_wiimote_event(struct wiimote_t* wm) {
    return wm->event;
}

unsigned short get_wiimote_btns(struct wiimote_t* wm) {
    return wm->btns;
}

unsigned short get_wiimote_btns_held(struct wiimote_t* wm) {
    return wm->btns_held;
}

unsigned short get_wiimote_btns_released(struct wiimote_t* wm) {
    return wm->btns_released;
}

float get_wiimote_battery_level(struct wiimote_t* wm) {
    return wm->battery_level;
}

// IR pointer functions
int get_wiimote_ir_found(struct wiimote_t* wm) {
    return wm->ir.num_dots;
}

int get_wiimote_ir_x(struct wiimote_t* wm) {
    return wm->ir.x;
}

int get_wiimote_ir_y(struct wiimote_t* wm) {
    return wm->ir.y;
}

float get_wiimote_ir_z(struct wiimote_t* wm) {
    return wm->ir.z;
}

// Accelerometer functions
unsigned char get_wiimote_accel_x(struct wiimote_t* wm) {
    return wm->accel.x;
}

unsigned char get_wiimote_accel_y(struct wiimote_t* wm) {
    return wm->accel.y;
}

unsigned char get_wiimote_accel_z(struct wiimote_t* wm) {
    return wm->accel.z;
}

// Gravity force functions
float get_wiimote_gforce_x(struct wiimote_t* wm) {
    return wm->gforce.x;
}

float get_wiimote_gforce_y(struct wiimote_t* wm) {
    return wm->gforce.y;
}

float get_wiimote_gforce_z(struct wiimote_t* wm) {
    return wm->gforce.z;
}

// Orientation functions
float get_wiimote_roll(struct wiimote_t* wm) {
    return wm->orient.roll;
}

float get_wiimote_pitch(struct wiimote_t* wm) {
    return wm->orient.pitch;
}

float get_wiimote_yaw(struct wiimote_t* wm) {
    return wm->orient.yaw;
}

// Individual IR dot functions
int get_wiimote_ir_dot_visible(struct wiimote_t* wm, int dot) {
    if (dot < 0 || dot >= 4) return 0;
    return wm->ir.dot[dot].visible;
}

int get_wiimote_ir_dot_x(struct wiimote_t* wm, int dot) {
    if (dot < 0 || dot >= 4) return 0;
    return wm->ir.dot[dot].x;
}

int get_wiimote_ir_dot_y(struct wiimote_t* wm, int dot) {
    if (dot < 0 || dot >= 4) return 0;
    return wm->ir.dot[dot].y;
}

int get_wiimote_ir_dot_size(struct wiimote_t* wm, int dot) {
    if (dot < 0 || dot >= 4) return 0;
    return wm->ir.dot[dot].size;
}

/* Expansion helpers */
int get_wiimote_expansion_type(struct wiimote_t* wm) {
    return wm->exp.type;
}

static unsigned char clamp_u8_int(int v) {
    if (v < 0) return 0;
    if (v > 255) return 255;
    return (unsigned char) v;
}

static unsigned char joystick_raw_from_normalized(float norm, unsigned char center, unsigned char min, unsigned char max) {
    float range = (norm >= 0.0f) ? (max - center) : (center - min);
    float raw = center + norm * range;
    int rounded = (int) (raw + (raw >= 0 ? 0.5f : -0.5f));
    return clamp_u8_int(rounded);
}

unsigned char get_nunchuk_stick_x_raw(struct wiimote_t* wm) {
    return joystick_raw_from_normalized(wm->exp.nunchuk.js.x,
                                        wm->exp.nunchuk.js.center.x,
                                        wm->exp.nunchuk.js.min.x,
                                        wm->exp.nunchuk.js.max.x);
}

unsigned char get_nunchuk_stick_y_raw(struct wiimote_t* wm) {
    return joystick_raw_from_normalized(wm->exp.nunchuk.js.y,
                                        wm->exp.nunchuk.js.center.y,
                                        wm->exp.nunchuk.js.min.y,
                                        wm->exp.nunchuk.js.max.y);
}

unsigned char get_nunchuk_accel_x(struct wiimote_t* wm) {
    return wm->exp.nunchuk.accel.x;
}

unsigned char get_nunchuk_accel_y(struct wiimote_t* wm) {
    return wm->exp.nunchuk.accel.y;
}

unsigned char get_nunchuk_accel_z(struct wiimote_t* wm) {
    return wm->exp.nunchuk.accel.z;
}

int get_nunchuk_button_c(struct wiimote_t* wm) {
    return (wm->exp.nunchuk.btns_held & NUNCHUK_BUTTON_C) != 0;
}

int get_nunchuk_button_z(struct wiimote_t* wm) {
    return (wm->exp.nunchuk.btns_held & NUNCHUK_BUTTON_Z) != 0;
}
