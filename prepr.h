#define NUMARGS(...)  (sizeof((int[]){__VA_ARGS__})/sizeof(int))

#define _Static_assert(...) (NUMARGS(__VA_ARGS__) == 1 ? (__VA_ARGS__, 0) : (__VA_ARGS__))
