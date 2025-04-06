module emu.hw.ipc.error;

enum IPCError {
    OK = 0,

    ENOENT = -2,
    EINVAL_DEVFS = -101,
    EEXIST_DEVFS = -105,
    ENOENT_DEVFS = -106,
}