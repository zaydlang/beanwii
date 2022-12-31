module util.file;

import util.number;

public u8[] load_file_as_bytes(string file_name) {
    import std.stdio;

    File file = File(file_name, "r");
    auto buffer = new ubyte[file.size()];
    file.rawRead(buffer);

    return cast(u8[]) buffer;
}
