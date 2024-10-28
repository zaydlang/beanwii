module test.nice_assert;

import std.stdio;

public void assert_eq(T)(T a, T b, string message = "") {
    if (a != b) {
        writefln("Assertion failed: ", message);
        writefln("Expected: %08x", a);
        writefln("Actual: %08x", b);
        assert(false);
    }
}