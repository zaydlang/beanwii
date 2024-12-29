module util.force_cast;

T force_cast(T, U)(U value) {
    return *(cast(T*) &value);
}