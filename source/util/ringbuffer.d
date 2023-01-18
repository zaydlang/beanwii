module util.ringbuffer;

final class RingBuffer(T) {
    T[] buffer;
    int current_index;

    this(size_t size) {
        current_index = 0;
        buffer = new T[size];
    }

    void add(T element) {
        if (buffer.length == 0) return;

        buffer[current_index] = element;
        current_index++;

        if (current_index >= buffer.length) current_index = 0;
    }

    T[] get() {
        T[] return_buffer = new T[buffer.length];

        for (int i = 0; i < buffer.length; i++) {
            return_buffer[i] = buffer[(i + current_index) % buffer.length];
        }

        return return_buffer;
    }
}
