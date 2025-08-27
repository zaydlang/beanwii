mem1 = list(open('mem1.bin', 'rb').read())


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
    
    def __repr__(self):
        return f"Thread(addr={hex(self.addr)}, state={self.state}, is_detached={self.is_detached}, " \
               f"suspend={self.suspend}, effective_priority={self.effective_priority}, " \
               f"base_priority={self.base_priority}, lr={hex(self.lr)})"

def read_u16(addr):
    addr -= 0x80000000
    return (mem1[addr] << 8) | mem1[addr + 1]

def read_u32(addr):
    addr -= 0x80000000
    return (mem1[addr] << 24) | (mem1[addr + 1] << 16) | (mem1[addr + 2] << 8) | mem1[addr + 3]

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