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