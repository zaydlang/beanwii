module emu.scheduler;

import util.log;

struct Event {
    void delegate() callback;
    ulong           timestamp;
	EventID         id;
    bool            completed;
}

alias EventID = ulong;

final class Scheduler {
    enum TOTAL_NUMBER_OF_EVENTS = 0x100;

    Event*[TOTAL_NUMBER_OF_EVENTS] events;
    
    int     events_in_queue;
    EventID id_counter;
    ulong   current_timestamp;
    bool    event_in_progress;
    Event   self;

    this() {
        for (int i = 0; i < TOTAL_NUMBER_OF_EVENTS; i++) {
        	events[i] = new Event(null, 0, 0, false);
        }
        
        events_in_queue   = 0;
        id_counter        = 0;
        current_timestamp = 0;
        event_in_progress = false;
    }

    ulong add_event_relative_to_clock(void delegate() callback, int delta_cycles) {
        return add_event(callback, current_timestamp + delta_cycles);
    }

    ulong add_event_relative_to_self(void delegate() callback, int delta_cycles) {
        return add_event(callback, self.timestamp + delta_cycles);
    }

    private ulong add_event(void delegate() callback, ulong timestamp) {
        log_scheduler("Adding event %d at %X", id_counter + 1, timestamp);
        int insert_at = 0;

        for (; insert_at < events_in_queue; insert_at++) {
            if (timestamp < events[insert_at].timestamp) {
            	break;
            }
        }
        
        for (int i = events_in_queue; i > insert_at; i--) {
            *events[i] = *events[i - 1];
        }
        
        id_counter++;
        events_in_queue++;
        *events[insert_at] = Event(callback, timestamp, id_counter);
        
        return id_counter;
    }

    void remove_event(ulong event_id) {
        int remove_at = -1;
        for (int i = 0; i < events_in_queue; i++) {
            if (events[i].id == event_id) {
            	remove_at = i;
                break;
            }
        }

        if (remove_at == -1) return;
        
        for (int i = remove_at; i < events_in_queue; i++) {
            *events[i] = *events[i + 1];
        }
        
        events_in_queue--;
    }

    pragma(inline, true) void tick(ulong num_cycles) {
        current_timestamp += num_cycles;
    }

    pragma(inline, true) void tick_to_next_event() {
        current_timestamp = events[0].timestamp;
    }

    pragma(inline, true) void process_events() {
        while (events_in_queue != 0 && current_timestamp >= events[0].timestamp) {
            process_event();
        }
    }

    pragma(inline, true) ulong get_current_time() {
        return current_timestamp;
    }

    pragma(inline, true) ulong get_current_time_relative_to_cpu() {
        return current_timestamp;
    }

    pragma(inline, true) ulong get_current_time_relative_to_self() {
        return events[0].timestamp;
    }

    pragma(inline, true) void process_event() {
        if (event_in_progress) return;

        event_in_progress = true;
        void delegate() cb = events[0].callback;
        log_scheduler("Firing event %d", events[0].id);
        self = *events[0];
        
        for (int i = 0; i < events_in_queue; i++) {
            *events[i] = *events[i + 1];
        }
        events_in_queue--;
        cb();
        
        event_in_progress = false;
    }

    void print_state() {
        log_scheduler("Current timestamp: %X", current_timestamp);
        log_scheduler("Events in queue: %d", events_in_queue);
        for (int i = 0; i < events_in_queue; i++) {
            log_scheduler("Event %d: %d", events[i].id, events[i].timestamp);
        }
    }
}