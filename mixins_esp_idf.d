alias atomic_uint_fast32_t = uint; alias atomic_intptr_t = ptrdiff_t; enum f = import("esp_idf.d"); mixin(f);

// ldc2 --mtriple=riscv32 --verrors=0 -Jpreprocessed -c mixins_esp_idf.d
