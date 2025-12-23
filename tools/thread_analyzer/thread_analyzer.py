mem1 = list(open('mem1.bin', 'rb').read())
mem2 = list(open('mem2.bin', 'rb').read())

#   state = PowerPC::MMU::HostRead_U16(guard, addr + 0x2c8);
#   is_detached = PowerPC::MMU::HostRead_U16(guard, addr + 0x2ca);
#   suspend = PowerPC::MMU::HostRead_U32(guard, addr + 0x2cc);
#   effective_priority = PowerPC::MMU::HostRead_U32(guard, addr + 0x2d0);
#   base_priority = PowerPC::MMU::HostRead_U32(guard, addr + 0x2d4);
#   exit_code_addr = PowerPC::MMU::HostRead_U32(guard, addr + 0x2d8);

#   queue_addr = PowerPC::MMU::HostRead_U32(guard, addr + 0x2dc);
#   queue_link.next = PowerPC::MMU::HostRead_U32(guard, addr + 0x2e0);
#   queue_link.prev = PowerPC::MMU::HostRead_U32(guard, addr + 0x2e4);

#   join_queue.head = PowerPC::MMU::HostRead_U32(guard, addr + 0x2e8);
#   join_queue.tail = PowerPC::MMU::HostRead_U32(guard, addr + 0x2ec);

#   mutex_addr = PowerPC::MMU::HostRead_U32(guard, addr + 0x2f0);
#   mutex_queue.head = PowerPC::MMU::HostRead_U32(guard, addr + 0x2f4);
#   mutex_queue.tail = PowerPC::MMU::HostRead_U32(guard, addr + 0x2f8);

#   thread_link.next = PowerPC::MMU::HostRead_U32(guard, addr + 0x2fc);
#   thread_link.prev = PowerPC::MMU::HostRead_U32(guard, addr + 0x300);

#   stack_addr = PowerPC::MMU::HostRead_U32(guard, addr + 0x304);
#   stack_end = PowerPC::MMU::HostRead_U32(guard, addr + 0x308);
#   error = PowerPC::MMU::HostRead_U32(guard, addr + 0x30c);
#   specific[0] = PowerPC::MMU::HostRead_U32(guard, addr + 0x310);
#   specific[1] = PowerPC::MMU::HostRead_U32(guard, addr + 0x314);

class Thread:
    def __init__(self, base_addr):
        self.state = read_u16(base_addr + 0x2c8)
        self.is_detached = read_u16(base_addr + 0x2ca)
        self.suspend = read_u32(base_addr + 0x2cc)
        self.effective_priority = read_u32(base_addr + 0x2d0)
        self.base_priority = read_u32(base_addr + 0x2d4)
        self.lr = read_u32(base_addr + 0x84)
        self.addr = base_addr
        self.stack_addr = read_u32(base_addr + 0x304)
        self.stack_end = read_u32(base_addr + 0x308)
        self.sp = read_u32(base_addr + 0x4)
    
    def __repr__(self):
        return f"Thread(addr={hex(self.addr)}, state={self.state}, is_detached={self.is_detached}, " \
               f"suspend={self.suspend}, effective_priority={self.effective_priority}, " \
               f"base_priority={self.base_priority}, lr={hex(self.lr)}), stack_addr={hex(self.stack_addr)} to {hex(self.stack_end)}, sp={hex(self.sp)}"
    
    def dump_stack(self):
        result = ""

        for addr in range(self.stack_end, self.stack_addr, 4):
            value = read_u32(addr)
            result += f"{hex(addr)}: {hex(value)}\n"
        
        return result

    def callstack(self, max_frames=16):
        frames = []
        sp = self.sp
        seen = set()
        stack_low = min(self.stack_end, self.stack_addr)
        stack_high = max(self.stack_end, self.stack_addr)

        for _ in range(max_frames):
            if sp in seen or sp in (0, 0xffffffff):
                break
            if not (stack_low <= sp <= stack_high):
                break
            if not is_valid_addr(sp, 4):
                break

            back_chain = read_u32(sp)
            lr_save = read_u32(sp + 4) if is_valid_addr(sp + 4, 4) else None

            frames.append((sp, back_chain, lr_save))
            seen.add(sp)
            sp = back_chain

        return frames

    def dump_callstack(self):
        lines = []
        for index, (sp, back_chain, lr_save) in enumerate(self.callstack()):
            lr_text = f"0x{lr_save:08x}" if lr_save is not None else "--------"
            lines.append(f"{index:02d}: sp=0x{sp:08x} back=0x{back_chain:08x} lr={lr_text}")

        if not lines:
            lines.append("(empty callstack)")

        return "\n".join(lines)

def read_u16(addr):
    if (addr >= 0x90000000):
        addr -= 0x90000000
        return (mem2[addr] << 8) | mem2[addr + 1]
    
    addr -= 0x80000000
    return (mem1[addr] << 8) | mem1[addr + 1]

def read_u32(addr):
    if (addr >= 0x90000000):
        addr -= 0x90000000
        return (mem2[addr] << 24) | (mem2[addr + 1] << 16) | (mem2[addr + 2] << 8) | mem2[addr + 3]
    
    addr -= 0x80000000
    return (mem1[addr] << 24) | (mem1[addr + 1] << 16) | (mem1[addr + 2] << 8) | mem1[addr + 3]

def is_valid_addr(addr, size=1):
    if addr >= 0x90000000:
        addr -= 0x90000000
        return 0 <= addr and addr + size <= len(mem2)

    if addr < 0x80000000:
        return False

    addr -= 0x80000000
    return 0 <= addr and addr + size <= len(mem1)

ACTIVE_QUEUE_HEAD_ADDR = 0x800000dc


active_thread = read_u32(ACTIVE_QUEUE_HEAD_ADDR)
threads = [active_thread]

# parse forward
current = active_thread
while current != 0:
    current = read_u32(current + 0x2fc)
    
    if current != 0:
        threads.append(current)

# parse backward
current = active_thread
while current != 0:
    current = read_u32(current + 0x300)
    
    if current != 0:
        threads.insert(0, current)

threads = [Thread(addr) for addr in threads if addr != 0]
print("Threads in the active queue:")
for thread in threads:
    print(thread)
    print(thread.dump_callstack())
    print()
