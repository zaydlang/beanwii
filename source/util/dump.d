module util.dump;

import emu.hw.memory.spec;
import std.stdio;
import util.number;

struct BeanDump {
    this(u32 entrypoint, u8[] mem1, u8[] mem2) {
        this.magic = 0x4245414E; // "BEAN"
        this.entrypoint = entrypoint;
        this.mem1 = mem1;
        this.mem2 = mem2;
    }

    align(1):
    u32 magic;
    u32 entrypoint;
    u8[MEM1_SIZE] mem1;
    u8[MEM2_SIZE] mem2;
}

void dump(BeanDump* bean_dump) {
    auto f = File("bean.bdp", "w+");
    f.rawWrite([*bean_dump]);
    f.close();
    
    File("mem1.bin", "w+").rawWrite(bean_dump.mem1);
    File("mem2.bin", "w+").rawWrite(bean_dump.mem2);
}
