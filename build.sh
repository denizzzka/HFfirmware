#!/usr/bin/env bash

set -euox pipefail

# Do not forgot to init ESP IDF environment:
# . ~/.../Espressif_IDE/esp-idf-v5.2.1/export.fish

# First stage: preprocess *.h to *.i files
PRESERVE_I_FILES=y idf.py --build-dir=preprocessed set-target esp32c3 build

# Mass rename *.c.i files to *.i (GCC produces *.c.i files for unknown reason)
mmv -r './preprocessed/;*.c.i' '#2.i'

# Preprocess *.i files applying importc.h to satisfy D compiler
PREP_FLAGS="-dD -Wno-builtin-macro-redefined -x c -E -include /home/denizzz/ldc2_standalone/import/importc.h"
fdfind --base-directory ./preprocessed/ --type f --glob *.i --exec clang $PREP_FLAGS -o ./'{//}'/'{/.}'.i '{}' \;

# Second stage: build and link with D files
idf.py --build-dir=builddir set-target esp32c3 build
