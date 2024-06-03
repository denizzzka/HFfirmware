#!/usr/bin/env bash

set -euox pipefail

# Do not forgot to init ESP IDF environment:
# . ~/.../Espressif_IDE/esp-idf-v5.2.1/export.fish

# First stage: preprocess *.h to *.i files
PRESERVE_I_FILES=y idf.py --build-dir=preprocessed set-target esp32c3 build

echo Processing *.i files...

# Mass rename *.c.i files to *.i (GCC produces *.c.i files for unknown reason)
mmv -r './preprocessed/;*.c.i' '#2.i'

# Preprocess *.i files applying importc.h and prepr.h to satisfy D compiler
# Also removes "# " lines to avoid using additional .h/.c files
PREPR_PATH=$(dirname "$(realpath $0)")/prepr.h
PREP_FLAGS="-dD -Wno-builtin-macro-redefined -x c -E -include /home/denizzz/ldc2_standalone/import/importc.h"
fdfind --base-directory ./preprocessed/ --type f --glob *.i --exec clang $PREP_FLAGS -include "${PREPR_PATH}" -o ./'{//}'/'{/.}'.i '{}' \; --exec sed -i -r 's/^# .+//g' {} \;

echo Processing *.i files done

# Second stage: build and link with D files
idf.py --build-dir=builddir set-target esp32c3 build
