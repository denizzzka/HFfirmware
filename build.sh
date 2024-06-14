#!/usr/bin/env bash

set -euox pipefail

# Do not forgot to init ESP IDF environment:
# . ~/.../Espressif_IDE/esp-idf-v5.2.1/export.fish

# First stage: preprocess *.h to *.i files
PRESERVE_I_FILES=y idf.py --build-dir=preprocessed set-target esp32c3 build

echo "Processing *.i files..."

# Removes definitions from .i files. For this purpose we need create intermediate conventional .c files from .i files
# Also removes "# " lines to avoid makeheaders tool errors
# restrict in freertos isn't compatible with __restrict in esp_ringbuf, ESP IDF issue?

fdfind --base-directory ./preprocessed/esp-idf --type f --glob "*.c.i" --ignore-file ../../fd_ignore.txt \
    --exec cp {} {.} \; \
    --exec sed -i -r 's/extern SLIST_HEAD/ SLIST_HEAD/g' {.} \; \
    --exec sed -i -r 's/asm volatile/__asm/g' {.} \; \
    --exec sed -i -r 's/__asm__/__asm/g' {.} \; \
    --exec sed -i -r 's/ asm / __asm /g' {.} \; \
    --exec sed -i -r 's/__restrict/restrict/g' {.} \; \
    --exec sed -i -r 's/__inline__/inline/g' {.} \; \
    --exec sed -i -r 's/__inline/inline/g' {.} \; \
    --exec sed -i -r 's/__volatile__/volatile/g' {.} \; \
    --exec sed -i -r 's/__typeof/typeof/g' {.} \; \
    --exec sed -i -r 's/typeof__/typeof/g' {.} \; \
    --exec sed -i -r 's/__attribute\(/__attribute__(/g' {.} \; \
    --exec sed -i -r 's/__attribute /__attribute__/g' {.} \; \
    --exec sed -i -r 's/__extension__//g' {.} \; \
    --exec echo ./preprocessed/esp-idf/{.} \; > preprocessed_files_list.txt

~/Dev/diprocessor/diprocessor --prepr_refs_comments < preprocessed_files_list.txt > ./preprocessed/processed_for_dpp.c
echo "./preprocessed/processed_for_dpp.c" | ~/Dev/diprocessor/peg/diprocessor_peg > ./preprocessed/processed_for_dpp.h

# Create D bindings from generated .c files
# FIXME: Used DPP branch: https://github.com/denizzzka/dpp/tree/c_and_i_files
~/Dev/dpp/bin/d++ --preprocess-only --no-sys-headers --include-path=./preprocessed/ --source-output-path=./preprocessed/ esp_idf.dpp

echo "Processing *.i files done"

# Second stage: build and link with D files
idf.py --build-dir=builddir set-target esp32c3 build
