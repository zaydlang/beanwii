module util.ringbuffer;

import util.log;

final class RingBuffer(T) {
    T[] buffer;
    int read_ptr;
    int write_ptr;
    int size;
    int total_size;

    this(int size) {
        this.read_ptr   = 0;
        this.write_ptr  = 0;
        this.size       = 0;
        this.total_size = size;
        this.buffer     = new T[size];
    }

    void add_overwrite(T element) {
        log_hollywood("Adding element to ring buffer: %s", element);
        size++;

        buffer[write_ptr] = element;
        
        write_ptr++;
        if (write_ptr >= total_size) write_ptr = 0;
    }

    void add(T element) {
        assert_util(size < total_size, "Ring buffer is full: %x < %x", size, total_size);
        add_overwrite(element);
    }

    T remove() {
        assert_util(size > 0, "Ring buffer is empty");

        size--;

        T element = buffer[read_ptr];

        read_ptr++;
        if (read_ptr >= total_size) read_ptr = 0;
    
        log_hollywood("Removing element from ring buffer %s", element);
        return element;
    }

    T[] get() {
        T[] return_buffer = new T[0];

        for (int i = read_ptr; i != write_ptr; i = (i + 1) % total_size) {
            return_buffer ~= buffer[i];
        }

        return return_buffer;
    }

    int get_size() {
        return size;
    }

    void clear() {
        read_ptr  = 0;
        write_ptr = 0;
        size      = 0;
    }
}
