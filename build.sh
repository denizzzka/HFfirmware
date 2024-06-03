#!/usr/bin/env bash

set -euox pipefail

# Do not forgot to init ESP IDF environment:
# . ~/.../Espressif_IDE/esp-idf-v5.2.1/export.fish

# First stage: preprocess *.h to *.i files
PRESERVE_I_FILES=y idf.py --build-dir=preprocessed set-target esp32c3 build

echo Processing *.i files...

# Removes definitions from .i files. For this purpose we need create intermediate conventional .c files from .i files
# Also removes "# " lines to avoid makeheaders tool errors
fdfind --base-directory ./preprocessed/ --type f --size +1b --glob "*.c.i" --ignore-file ../fd_ignore.txt \
    --exec cp {} {.} \; \
    --exec sed -i -r 's/^# .+//g' {.} \; \
    --exec ~/Dev/makeheaders/builddir/makeheaders {.} \; \
    --exec rm {.} \;

# Create .c bindings from generated .h headers (D compiler isn't handles .h files directly)
fdfind --base-directory ./preprocessed/ --type f --glob "*.h" --exec mv {} {.}.c \;

echo Processing *.i files done

# Second stage: build and link with D files
idf.py --build-dir=builddir set-target esp32c3 build
