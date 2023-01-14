module util.dump;

import util.number;

void dump(u8[] data, string file_name) {
    import std.file;
    import std.stdio;

    auto f = File(file_name, "w+");
    f.rawWrite(cast(u8[]) data);
    f.close();
}
